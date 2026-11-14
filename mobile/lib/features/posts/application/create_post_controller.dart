import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import '../data/models/post_category.dart';
import '../data/models/post_detail.dart';
import '../data/post_repository.dart';
import 'create_post_attachments_controller.dart';
import 'create_post_local_attachment.dart';
import 'create_post_session_persistence.dart';
import 'create_post_uncertain_upload_record.dart';

enum CreatePostPhase { idle, submitting, submitted }

class CreatePostWorkflowState {
  const CreatePostWorkflowState({
    this.phase = CreatePostPhase.idle,
    this.confirmedDraftId,
    this.uncertainCreate = false,
  });

  final CreatePostPhase phase;
  final int? confirmedDraftId;
  final bool uncertainCreate;

  bool get hasDraftAwaitingSubmit => confirmedDraftId != null;

  /// Bloquea un nuevo POST /posts mientras no haya ID confirmado ni recuperación explícita.
  bool get blocksFullSend => uncertainCreate && confirmedDraftId == null;

  CreatePostWorkflowState copyWith({
    CreatePostPhase? phase,
    int? confirmedDraftId,
    bool? uncertainCreate,
    bool clearDraftId = false,
    bool clearUncertain = false,
  }) {
    return CreatePostWorkflowState(
      phase: phase ?? this.phase,
      confirmedDraftId:
          clearDraftId ? null : (confirmedDraftId ?? this.confirmedDraftId),
      uncertainCreate:
          clearUncertain ? false : (uncertainCreate ?? this.uncertainCreate),
    );
  }
}

sealed class CreatePostSendResult {
  const CreatePostSendResult();
}

class CreatePostSendSuccess extends CreatePostSendResult {
  const CreatePostSendSuccess(this.detail);

  final PostDetail detail;
}

class CreatePostSendDiscarded extends CreatePostSendResult {
  const CreatePostSendDiscarded();
}

class CreatePostSendInFlight extends CreatePostSendResult {
  const CreatePostSendInFlight();
}

class CreatePostSendNoSession extends CreatePostSendResult {
  const CreatePostSendNoSession();
}

class CreatePostSendCreateFailed extends CreatePostSendResult {
  const CreatePostSendCreateFailed(this.failure);

  final ApiFailure failure;
}

class CreatePostSendDraftOnly extends CreatePostSendResult {
  const CreatePostSendDraftOnly(this.draftId, this.failure);

  final int draftId;
  final ApiFailure failure;
}

class CreatePostSendUncertain extends CreatePostSendResult {
  const CreatePostSendUncertain();
}

class CreatePostSendDraftLinked extends CreatePostSendResult {
  const CreatePostSendDraftLinked(this.draftId);

  final int draftId;
}

class CreatePostSendAlreadyPending extends CreatePostSendResult {
  const CreatePostSendAlreadyPending(this.detail);

  final PostDetail detail;
}

class CreatePostSendAttachmentsBlocked extends CreatePostSendResult {
  const CreatePostSendAttachmentsBlocked(this.message);

  final String message;
}

class CreatePostSendUploadFailure extends CreatePostSendResult {
  const CreatePostSendUploadFailure(this.draftId, this.failure);

  final int draftId;
  final ApiFailure failure;
}

class CreatePostSendUploadUncertain extends CreatePostSendResult {
  const CreatePostSendUploadUncertain(this.draftId);

  final int draftId;
}

class CreatePostSendReconcileInconclusive extends CreatePostSendResult {
  const CreatePostSendReconcileInconclusive(this.draftId);

  final int draftId;
}

class CreatePostSendDraftPending extends CreatePostSendResult {
  const CreatePostSendDraftPending(this.detail);

  final PostDetail detail;
}

class CreatePostController
    extends AutoDisposeNotifier<CreatePostWorkflowState> {
  bool _submitInFlight = false;
  bool _reconcileInFlight = false;
  int _submitGeneration = 0;
  int? _trackedSessionEpoch;
  int? _hydratedDraftIdForEpoch;
  CreatePostPhase _uiPhase = CreatePostPhase.idle;
  CancelToken? _uploadCancelToken;

  CreatePostSessionPersistenceState get _sessionPersistence =>
      ref.read(createPostSessionPersistenceProvider);

  @override
  CreatePostWorkflowState build() {
    final epoch = ref.watch(createPostSessionEpochProvider);
    final persisted = ref.read(createPostSessionPersistenceProvider);
    if (epoch == null) {
      _trackedSessionEpoch = null;
      _submitInFlight = false;
      _uiPhase = CreatePostPhase.idle;
      return const CreatePostWorkflowState();
    }

    if (_trackedSessionEpoch != epoch) {
      _trackedSessionEpoch = epoch;
      _submitInFlight = false;
      _reconcileInFlight = false;
      _hydratedDraftIdForEpoch = null;
      _submitGeneration++;
      _uiPhase = CreatePostPhase.idle;
      return _hydrateFromPersistence(persisted, _uiPhase);
    }

    return _hydrateFromPersistence(persisted, _uiPhase);
  }

  void _setWorkflow(CreatePostWorkflowState next) {
    _uiPhase = next.phase;
    state = next;
  }

  CreatePostWorkflowState _hydrateFromPersistence(
    CreatePostSessionPersistenceState persisted,
    CreatePostPhase phase,
  ) {
    return CreatePostWorkflowState(
      phase: phase,
      confirmedDraftId: persisted.confirmedDraftId,
      uncertainCreate: persisted.uncertainCreate,
    );
  }

  void _persistUncertain() {
    ref
        .read(createPostSessionPersistenceProvider.notifier)
        .markUncertainCreate();
  }

  void _persistDraftId(int id, {required bool clearUncertain}) {
    ref
        .read(createPostSessionPersistenceProvider.notifier)
        .setConfirmedDraftId(id, clearUncertain: clearUncertain);
  }

  void _persistClearAll() {
    ref.read(createPostSessionPersistenceProvider.notifier).clearAll();
  }

  void releaseStaleSubmitUi() {
    if (_uiPhase == CreatePostPhase.submitting) {
      _setWorkflow(
        _hydrateFromPersistence(_sessionPersistence, CreatePostPhase.idle),
      );
    }
    _submitInFlight = false;
  }

  void resetAfterSuccess() {
    _persistClearAll();
    ref.read(createPostAttachmentsProvider.notifier).clearAll();
    _uploadCancelToken?.cancel();
    _uploadCancelToken = null;
    _uiPhase = CreatePostPhase.idle;
    _setWorkflow(const CreatePostWorkflowState());
    ++_submitGeneration;
  }

  Future<CreatePostSendResult> reconcileUploadsFromServer() async {
    if (_reconcileInFlight || _submitInFlight) {
      return const CreatePostSendInFlight();
    }
    final draftId =
        _sessionPersistence.confirmedDraftId ?? state.confirmedDraftId;
    if (draftId == null) {
      return const CreatePostSendCreateFailed(ApiUnexpectedFailure());
    }
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return const CreatePostSendNoSession();
    }
    final generation = ++_submitGeneration;
    _reconcileInFlight = true;
    try {
      final detail = await ref.read(postRepositoryProvider).getPost(draftId);
      if (!_stillSameSession(epoch, generation)) {
        return const CreatePostSendDiscarded();
      }
      if (detail.status == 'pending') {
        ref
            .read(createPostSessionPersistenceProvider.notifier)
            .setLinkedDraftPending(true);
        return CreatePostSendDraftPending(detail);
      }
      final revisionId =
          detail.editableRevisionId ?? _sessionPersistence.confirmedRevisionId;
      if (revisionId == null) {
        return const CreatePostSendCreateFailed(ApiUnexpectedFailure());
      }
      final serverIds = detail.attachments.map((a) => a.id).toList();
      final sessionBeforeSync = ref.read(createPostSessionPersistenceProvider);
      final unresolvedBefore =
          sessionBeforeSync.hasUnresolvedUncertainUpload ||
          ref
              .read(createPostAttachmentsProvider)
              .hasBlockingUncertain(sessionBeforeSync);
      ref
          .read(createPostSessionPersistenceProvider.notifier)
          .syncServerAttachments(
            revisionId: revisionId,
            attachmentIds: serverIds,
          );
      ref
          .read(createPostAttachmentsProvider.notifier)
          .applyServerAttachmentSnapshot(
            serverAttachmentIds: serverIds,
            unresolvedUncertain: unresolvedBefore,
          );
      final session = ref.read(createPostSessionPersistenceProvider);
      final attachments = ref.read(createPostAttachmentsProvider);
      if (session.hasUnresolvedUncertainUpload ||
          attachments.hasBlockingUncertain(session)) {
        return CreatePostSendReconcileInconclusive(draftId);
      }
      return CreatePostSendDraftLinked(draftId);
    } on ApiFailure catch (e) {
      if (neighborhoodSessionEpoch(ref) != epoch) {
        return const CreatePostSendDiscarded();
      }
      return CreatePostSendCreateFailed(e);
    } finally {
      if (neighborhoodSessionEpoch(ref) == epoch &&
          generation == _submitGeneration) {
        _reconcileInFlight = false;
      }
    }
  }

  /// GET controlado al reingresar con borrador confirmado (una vez por borrador/epoch).
  Future<void> hydrateConfirmedDraftIfNeeded() async {
    final draftId =
        _sessionPersistence.confirmedDraftId ?? state.confirmedDraftId;
    if (draftId == null) {
      return;
    }
    if (_hydratedDraftIdForEpoch == draftId || _submitInFlight) {
      return;
    }
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return;
    }
    final generation = ++_submitGeneration;
    try {
      final detail = await ref.read(postRepositoryProvider).getPost(draftId);
      if (!_stillSameSession(epoch, generation)) {
        return;
      }
      _hydratedDraftIdForEpoch = draftId;
      if (detail.status == 'pending') {
        ref
            .read(createPostSessionPersistenceProvider.notifier)
            .setLinkedDraftPending(true);
        _setWorkflow(
          const CreatePostWorkflowState(phase: CreatePostPhase.submitted),
        );
        return;
      }
      if (detail.status != 'draft' && detail.status != 'rejected') {
        return;
      }
      final revisionId = detail.editableRevisionId;
      if (revisionId != null) {
        ref
            .read(createPostSessionPersistenceProvider.notifier)
            .setConfirmedRevisionId(revisionId);
      }
      ref
          .read(createPostAttachmentsProvider.notifier)
          .syncFromPostDetail(detail);
    } on ApiFailure {
      // Conservador: no limpiar incertidumbres ni flags locales.
    }
  }

  Future<CreatePostSendResult> sendForReview({
    required int neighborhoodGroupId,
    required int categoryId,
    required String title,
    required String body,
  }) async {
    if (_submitInFlight) {
      return const CreatePostSendInFlight();
    }

    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return const CreatePostSendNoSession();
    }

    final persisted = _sessionPersistence;
    if (persisted.blocksFullSend) {
      if (persisted.hasUnresolvedUncertainUpload) {
        final draft = persisted.confirmedDraftId ?? state.confirmedDraftId;
        if (draft != null) {
          return CreatePostSendUploadUncertain(draft);
        }
      }
      if (persisted.linkedDraftPending) {
        return const CreatePostSendAttachmentsBlocked(
          'Este borrador ya está en moderación.',
        );
      }
      return const CreatePostSendUncertain();
    }

    final attachmentsState = ref.read(createPostAttachmentsProvider);
    if (attachmentsState.hasUploading) {
      return const CreatePostSendInFlight();
    }
    if (attachmentsState.hasBlockingUncertain(persisted)) {
      final draft = persisted.confirmedDraftId ?? state.confirmedDraftId;
      if (draft != null) {
        return CreatePostSendUploadUncertain(draft);
      }
      return const CreatePostSendAttachmentsBlocked(
        'Hay archivos con resultado incierto. Verifica antes de enviar.',
      );
    }

    if (persisted.linkedDraftPending) {
      return const CreatePostSendAttachmentsBlocked(
        'Este borrador ya está en moderación. No puedes subir ni enviar de nuevo.',
      );
    }

    final existingDraftId =
        persisted.confirmedDraftId ?? state.confirmedDraftId;
    if (existingDraftId != null) {
      final uploadResult = await _uploadPendingAttachments(
        postId: existingDraftId,
        epoch: epoch,
      );
      if (uploadResult != null) {
        return uploadResult;
      }
      return _submitOnly(postId: existingDraftId, epoch: epoch);
    }

    final generation = ++_submitGeneration;
    _submitInFlight = true;
    _setWorkflow(
      _hydrateFromPersistence(_sessionPersistence, CreatePostPhase.submitting),
    );

    try {
      final created = await ref
          .read(postRepositoryProvider)
          .createCommunityPost(
            neighborhoodGroupId: neighborhoodGroupId,
            categoryId: categoryId,
            title: title,
            body: body,
          );

      if (!_stillSameSession(epoch, generation)) {
        return const CreatePostSendDiscarded();
      }

      _persistDraftId(created.id, clearUncertain: true);
      final revisionId = created.editableRevisionId;
      if (revisionId == null) {
        return const CreatePostSendCreateFailed(ApiUnexpectedFailure());
      }
      ref
          .read(createPostSessionPersistenceProvider.notifier)
          .setConfirmedRevisionId(revisionId);
      ref
          .read(createPostAttachmentsProvider.notifier)
          .syncFromPostDetail(created);
      _setWorkflow(
        CreatePostWorkflowState(phase: _uiPhase, confirmedDraftId: created.id),
      );

      final uploadResult = await _uploadPendingAttachments(
        postId: created.id,
        epoch: epoch,
        generation: generation,
        revisionId: revisionId,
      );
      if (uploadResult != null) {
        return uploadResult;
      }

      return await _submitOnly(
        postId: created.id,
        epoch: epoch,
        generation: generation,
        skipGenerationBump: true,
      );
    } on ApiFailure catch (e) {
      if (!_stillSameSession(epoch, generation)) {
        return const CreatePostSendDiscarded();
      }

      final draftId =
          _sessionPersistence.confirmedDraftId ?? state.confirmedDraftId;
      if (draftId != null) {
        _setWorkflow(
          _hydrateFromPersistence(_sessionPersistence, CreatePostPhase.idle),
        );
        return CreatePostSendDraftOnly(draftId, e);
      }

      _setWorkflow(
        _hydrateFromPersistence(_sessionPersistence, CreatePostPhase.idle),
      );
      return CreatePostSendCreateFailed(e);
    } catch (_) {
      if (!_stillSameSession(epoch, generation)) {
        return const CreatePostSendDiscarded();
      }

      _persistUncertain();
      _setWorkflow(
        _hydrateFromPersistence(_sessionPersistence, CreatePostPhase.idle),
      );
      return const CreatePostSendUncertain();
    } finally {
      _submitInFlight = false;
    }
  }

  Future<CreatePostSendResult> retrySubmitOnly() async {
    if (_submitInFlight || _reconcileInFlight) {
      return const CreatePostSendInFlight();
    }
    final draftId =
        _sessionPersistence.confirmedDraftId ?? state.confirmedDraftId;
    if (draftId == null) {
      return const CreatePostSendCreateFailed(ApiUnexpectedFailure());
    }

    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return const CreatePostSendNoSession();
    }
    if (_sessionPersistence.linkedDraftPending) {
      return const CreatePostSendAttachmentsBlocked(
        'Este borrador ya está en moderación.',
      );
    }

    final uploadResult = await _uploadPendingAttachments(
      postId: draftId,
      epoch: epoch,
    );
    if (uploadResult != null) {
      return uploadResult;
    }

    if (_sessionPersistence.hasUnresolvedUncertainUpload) {
      return CreatePostSendUploadUncertain(draftId);
    }

    return _submitOnly(postId: draftId, epoch: epoch);
  }

  Future<CreatePostSendResult> refreshDraftStatusAndMaybeSubmit() async {
    if (_submitInFlight || _reconcileInFlight) {
      return const CreatePostSendInFlight();
    }
    final draftId =
        _sessionPersistence.confirmedDraftId ?? state.confirmedDraftId;
    if (draftId == null) {
      return const CreatePostSendCreateFailed(ApiUnexpectedFailure());
    }

    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return const CreatePostSendNoSession();
    }

    final generation = ++_submitGeneration;

    try {
      final detail = await ref.read(postRepositoryProvider).getPost(draftId);
      if (!_stillSameSession(epoch, generation)) {
        return const CreatePostSendDiscarded();
      }

      if (detail.status == 'pending') {
        _persistClearAll();
        _setWorkflow(
          const CreatePostWorkflowState(phase: CreatePostPhase.submitted),
        );
        return CreatePostSendSuccess(detail);
      }

      if (detail.status == 'draft' || detail.status == 'rejected') {
        return _submitOnly(
          postId: draftId,
          epoch: epoch,
          generation: generation,
        );
      }

      _setWorkflow(
        _hydrateFromPersistence(_sessionPersistence, CreatePostPhase.idle),
      );
      return CreatePostSendSuccess(detail);
    } on ApiFailure catch (e) {
      if (neighborhoodSessionEpoch(ref) != epoch) {
        return const CreatePostSendDiscarded();
      }
      return CreatePostSendCreateFailed(e);
    }
  }

  /// Enlaza un borrador elegido explícitamente tras un create incierto (sin auto-selección).
  Future<CreatePostSendResult> linkExplicitRecoveryDraft(int postId) async {
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return const CreatePostSendNoSession();
    }

    final confirmed =
        _sessionPersistence.confirmedDraftId ?? state.confirmedDraftId;
    if (confirmed != null && confirmed != postId) {
      return const CreatePostSendCreateFailed(ApiUnexpectedFailure());
    }

    final generation = ++_submitGeneration;

    try {
      final detail = await ref.read(postRepositoryProvider).getPost(postId);
      if (!_stillSameSession(epoch, generation)) {
        return const CreatePostSendDiscarded();
      }

      if (detail.status == 'pending') {
        _setWorkflow(
          _hydrateFromPersistence(_sessionPersistence, CreatePostPhase.idle),
        );
        return CreatePostSendAlreadyPending(detail);
      }

      if (detail.status != 'draft' && detail.status != 'rejected') {
        return const CreatePostSendCreateFailed(ApiUnexpectedFailure());
      }

      _persistDraftId(postId, clearUncertain: true);
      final revisionId = detail.editableRevisionId;
      if (revisionId != null) {
        ref
            .read(createPostSessionPersistenceProvider.notifier)
            .setConfirmedRevisionId(revisionId);
      }
      ref
          .read(createPostAttachmentsProvider.notifier)
          .syncFromPostDetail(detail);
      _setWorkflow(
        CreatePostWorkflowState(
          phase: CreatePostPhase.idle,
          confirmedDraftId: postId,
        ),
      );
      return CreatePostSendDraftLinked(postId);
    } on ApiFailure catch (e) {
      if (neighborhoodSessionEpoch(ref) != epoch) {
        return const CreatePostSendDiscarded();
      }
      return CreatePostSendCreateFailed(e);
    }
  }

  Future<CreatePostSendResult> _submitOnly({
    required int postId,
    required int epoch,
    int? generation,
    bool skipGenerationBump = false,
  }) async {
    if (_submitInFlight && !skipGenerationBump) {
      return const CreatePostSendInFlight();
    }

    final submitGeneration = generation ?? ++_submitGeneration;
    if (generation == null) {
      _submitInFlight = true;
      _setWorkflow(
        _hydrateFromPersistence(
          _sessionPersistence,
          CreatePostPhase.submitting,
        ),
      );
    }

    try {
      final submitted = await ref
          .read(postRepositoryProvider)
          .submitPost(postId);

      if (!_stillSameSession(epoch, submitGeneration)) {
        return const CreatePostSendDiscarded();
      }

      if (submitted.status == 'pending' || submitted.status == 'published') {
        _persistClearAll();
        _setWorkflow(
          const CreatePostWorkflowState(phase: CreatePostPhase.submitted),
        );
        return CreatePostSendSuccess(submitted);
      }

      _persistDraftId(postId, clearUncertain: true);
      _setWorkflow(
        CreatePostWorkflowState(
          phase: CreatePostPhase.idle,
          confirmedDraftId: postId,
        ),
      );
      return CreatePostSendSuccess(submitted);
    } on ApiFailure catch (e) {
      if (!_stillSameSession(epoch, submitGeneration)) {
        return const CreatePostSendDiscarded();
      }
      _persistDraftId(postId, clearUncertain: false);
      _setWorkflow(
        CreatePostWorkflowState(
          phase: CreatePostPhase.idle,
          confirmedDraftId: postId,
        ),
      );
      return CreatePostSendDraftOnly(postId, e);
    } finally {
      if (generation == null) {
        _submitInFlight = false;
      }
    }
  }

  bool _stillSameSession(int epoch, int generation) {
    return neighborhoodSessionEpoch(ref) == epoch &&
        generation == _submitGeneration;
  }

  Future<CreatePostSendResult?> _uploadPendingAttachments({
    required int postId,
    required int epoch,
    int? generation,
    int? revisionId,
  }) async {
    final gen = generation ?? _submitGeneration;
    final persistence = _sessionPersistence;
    final attachments = ref.read(createPostAttachmentsProvider);
    final uncertainIds =
        persistence.uncertainUploadRecords.map((e) => e.clientId).toSet();
    final pending =
        attachments.needsUpload
            .where((e) => !uncertainIds.contains(e.clientId))
            .toList();
    final blockedPending =
        attachments.needsUpload
            .where((e) => uncertainIds.contains(e.clientId))
            .toList();
    if (blockedPending.isNotEmpty) {
      return CreatePostSendUploadUncertain(postId);
    }
    if (pending.isEmpty) {
      return null;
    }

    int? resolvedRevision = revisionId;
    if (resolvedRevision == null) {
      final detail = await ref.read(postRepositoryProvider).getPost(postId);
      if (!_stillSameSession(epoch, gen)) {
        return const CreatePostSendDiscarded();
      }
      if (detail.status == 'pending') {
        ref
            .read(createPostSessionPersistenceProvider.notifier)
            .setLinkedDraftPending(true);
        return const CreatePostSendAttachmentsBlocked(
          'Este borrador ya está en moderación. No se pueden subir adjuntos.',
        );
      }
      resolvedRevision = detail.editableRevisionId;
      if (resolvedRevision == null) {
        return CreatePostSendUploadFailure(
          postId,
          const ApiUnexpectedFailure(),
        );
      }
      ref
          .read(createPostAttachmentsProvider.notifier)
          .syncFromPostDetail(detail);
    }

    ref
        .read(createPostSessionPersistenceProvider.notifier)
        .setConfirmedRevisionId(resolvedRevision);

    _uploadCancelToken?.cancel();
    _uploadCancelToken = CancelToken();

    final notifier = ref.read(createPostAttachmentsProvider.notifier);

    for (final item in pending) {
      if (!_stillSameSession(epoch, gen)) {
        _uploadCancelToken?.cancel();
        return const CreatePostSendDiscarded();
      }

      if (!File(item.path).existsSync()) {
        notifier.applyItemUpdate(
          item.copyWith(
            state: CreatePostAttachmentState.failed,
            userMessage:
                'El archivo ya no está disponible. Selecciónalo de nuevo.',
          ),
        );
        return CreatePostSendAttachmentsBlocked(
          'Un archivo local ya no está disponible.',
        );
      }

      notifier.applyItemUpdate(
        item.copyWith(
          state: CreatePostAttachmentState.uploading,
          uploadProgress: 0,
          clearUserMessage: true,
        ),
      );

      try {
        final result = await ref
            .read(postRepositoryProvider)
            .uploadPostAttachment(
              postId: postId,
              revisionId: resolvedRevision,
              filePath: item.path,
              filename: item.displayName,
              mimeType: item.mimeType,
              cancelToken: _uploadCancelToken,
              onSendProgress: (sent, total) {
                if (total > 0) {
                  notifier.applyItemUpdate(
                    item.copyWith(
                      state: CreatePostAttachmentState.uploading,
                      uploadProgress: sent / total,
                    ),
                  );
                }
              },
            );

        if (!_stillSameSession(epoch, gen)) {
          return const CreatePostSendDiscarded();
        }

        ref
            .read(createPostSessionPersistenceProvider.notifier)
            .recordUploadedAttachment(result.id);
        ref
            .read(createPostSessionPersistenceProvider.notifier)
            .resolveUncertainUpload(item.clientId);
        notifier.applyItemUpdate(
          item.copyWith(
            state: CreatePostAttachmentState.uploaded,
            serverAttachmentId: result.id,
            clearProgress: true,
          ),
        );
      } on ApiFailure catch (e) {
        if (!_stillSameSession(epoch, gen)) {
          return const CreatePostSendDiscarded();
        }
        _persistDraftId(postId, clearUncertain: false);
        notifier.applyItemUpdate(
          item.copyWith(
            state: CreatePostAttachmentState.failed,
            userMessage: e.userMessage,
            clearProgress: true,
          ),
        );
        return CreatePostSendUploadFailure(postId, e);
      } catch (_) {
        if (!_stillSameSession(epoch, gen)) {
          return const CreatePostSendDiscarded();
        }
        ref
            .read(createPostSessionPersistenceProvider.notifier)
            .registerUncertainUpload(
              CreatePostUncertainUploadRecord(
                clientId: item.clientId,
                displayName: item.displayName,
                sizeBytes: item.sizeBytes,
                mimeType: item.mimeType,
                localPath: item.path,
              ),
            );
        notifier.applyItemUpdate(
          item.copyWith(
            state: CreatePostAttachmentState.uncertain,
            userMessage:
                'No pudimos confirmar si el archivo se subió. Verifica antes de reintentar.',
            clearProgress: true,
          ),
        );
        return CreatePostSendUploadUncertain(postId);
      }
    }

    _uploadCancelToken = null;
    return null;
  }
}

final postCategoriesProvider = FutureProvider.autoDispose<List<PostCategory>>((
  ref,
) async {
  ref.watch(authControllerProvider);
  final auth = ref.read(authControllerProvider);
  if (auth is! AuthAuthenticated) {
    return const [];
  }
  final epoch = neighborhoodSessionEpoch(ref);
  if (epoch == null) {
    return const [];
  }
  final categories = await ref
      .read(postRepositoryProvider)
      .listPostCategories(audience: 'group');
  if (neighborhoodSessionEpoch(ref) != epoch) {
    throw const ApiSessionExpiredFailure();
  }
  return categories;
});

final createPostControllerProvider =
    NotifierProvider.autoDispose<CreatePostController, CreatePostWorkflowState>(
      CreatePostController.new,
    );

bool isNeighborhoodGroupEligibleForPosting(String status) => status == 'active';
