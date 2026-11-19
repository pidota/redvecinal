import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import '../data/models/post_detail.dart';
import '../data/models/post_moderation_review_state.dart';
import '../data/post_attachment_storage.dart';
import '../data/post_moderation_failure.dart';
import '../data/post_repository.dart';
import 'feed_controller.dart';
import 'post_detail_controller.dart';
import 'post_moderation_approve_support.dart';
import 'post_moderation_review_key.dart';
import 'post_moderation_uncertain_approve_persistence.dart';
import 'post_moderation_uncertain_approve_record.dart';
import 'post_pending_queue_controller.dart';

class PostModerationReviewController
    extends
        AutoDisposeFamilyAsyncNotifier<
          PostModerationReviewState,
          PostModerationReviewKey
        > {
  int _loadGeneration = 0;
  int? _activeDecisionGeneration;
  int _decisionAttemptGeneration = 0;

  PostModerationUncertainApprovePersistence get _approvePersistence =>
      ref.read(postModerationUncertainApprovePersistenceProvider.notifier);

  @override
  Future<PostModerationReviewState> build(PostModerationReviewKey key) {
    ref.watch(authControllerProvider);
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return Future.error(StateError('Sin sesión'));
    }
    return _load(key, epoch);
  }

  Future<void> refresh() async {
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      state = AsyncValue.error(StateError('Sin sesión'), StackTrace.current);
      return;
    }

    final generation = ++_loadGeneration;
    final previous = state.valueOrNull;
    if (previous == null) {
      state = const AsyncValue.loading();
    } else {
      state = AsyncValue<PostModerationReviewState>.loading().copyWithPrevious(
        AsyncValue.data(previous),
      );
    }

    try {
      final next = await _load(arg, epoch);
      if (generation != _loadGeneration) {
        return;
      }
      if (neighborhoodSessionEpoch(ref) != epoch) {
        if (previous != null) {
          state = AsyncValue.data(previous);
        }
        return;
      }
      state = AsyncValue.data(_enrichWithPersistenceFlags(next));
    } catch (e, st) {
      if (generation != _loadGeneration) {
        if (previous != null) {
          state = AsyncValue.data(previous);
        }
        return;
      }
      state = AsyncValue.error(e, st);
    }
  }

  Future<PostAttachmentDownloadResult> downloadAttachment(
    PostAttachment attachment,
  ) async {
    final epochBefore = neighborhoodSessionEpoch(ref);
    final auth = ref.read(authControllerProvider);
    if (epochBefore == null || auth is! AuthAuthenticated) {
      return const PostAttachmentDownloadResult.sessionEnded();
    }
    final userId = auth.user.id;
    final postId = arg.postId;

    try {
      final bytes = await ref
          .read(postRepositoryProvider)
          .downloadAttachment(
            postId: postId,
            attachmentId: attachment.id,
            relativePath: attachment.relativeDownloadPath,
          );

      if (neighborhoodSessionEpoch(ref) != epochBefore) {
        return const PostAttachmentDownloadResult.sessionEnded();
      }

      final authAfterDownload = ref.read(authControllerProvider);
      if (authAfterDownload is! AuthAuthenticated ||
          authAfterDownload.user.id != userId) {
        await ref.read(postAttachmentStorageProvider).invalidate();
        return const PostAttachmentDownloadResult.sessionEnded();
      }

      final storage = ref.read(postAttachmentStorageProvider);
      final saved = await storage.saveForSession(
        sessionEpoch: epochBefore,
        userId: userId,
        fileName: '${attachment.id}_${attachment.sanitizedFileName}',
        bytes: bytes,
      );

      if (neighborhoodSessionEpoch(ref) != epochBefore) {
        await storage.invalidate();
        return const PostAttachmentDownloadResult.sessionEnded();
      }

      final authAfterSave = ref.read(authControllerProvider);
      if (authAfterSave is! AuthAuthenticated ||
          authAfterSave.user.id != userId) {
        await storage.invalidate();
        return const PostAttachmentDownloadResult.sessionEnded();
      }

      if (saved.sessionInvalidated) {
        return const PostAttachmentDownloadResult.sessionEnded();
      }
      if (saved.failed || !saved.saved) {
        return const PostAttachmentDownloadResult.failed();
      }

      return PostAttachmentDownloadResult.success(saved.path!);
    } catch (_) {
      if (neighborhoodSessionEpoch(ref) != epochBefore) {
        return const PostAttachmentDownloadResult.sessionEnded();
      }
      rethrow;
    }
  }

  Future<PostModerationReviewState> _load(
    PostModerationReviewKey key,
    int epoch,
  ) async {
    final detail = await ref.read(postRepositoryProvider).getPost(key.postId);
    if (neighborhoodSessionEpoch(ref) != epoch) {
      throw StateError('Respuesta de sesión anterior');
    }
    final reviewState = PostModerationReviewState.fromDetail(
      detail: detail,
      expectedGroupId: key.groupId,
    );
    return _enrichWithPersistenceFlags(reviewState);
  }

  PostModerationReviewState _enrichWithPersistenceFlags(
    PostModerationReviewState base,
  ) {
    final record = _approvePersistence.recordFor(arg.postId);
    if (record == null) {
      return base;
    }
    switch (record.phase) {
      case PostModerationUncertainApprovePhase.inFlight:
        return base.copyWith(approveInFlight: true, approveUncertain: false);
      case PostModerationUncertainApprovePhase.outcomeUncertain:
        return base.copyWith(approveInFlight: false, approveUncertain: true);
    }
  }

  int? _authenticatedUserId() {
    final auth = ref.read(authControllerProvider);
    if (auth is AuthAuthenticated) {
      return auth.user.id;
    }
    return null;
  }

  bool _decisionAttemptStillActive({
    required int operationGeneration,
    required int userId,
    required int sessionEpoch,
    required int decisionGeneration,
  }) {
    if (neighborhoodSessionEpoch(ref) != sessionEpoch) {
      return false;
    }
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated || auth.user.id != userId) {
      return false;
    }
    if (_activeDecisionGeneration != decisionGeneration) {
      return false;
    }
    if (!_approvePersistence.sessionBindingActiveFor(userId, sessionEpoch)) {
      return false;
    }
    final record = _approvePersistence.peekRecordForPost(arg.postId);
    if (record == null) {
      return false;
    }
    return record.operationGeneration == operationGeneration;
  }

  Future<PostModerationApproveResult> approvePublication() async {
    final current = state.valueOrNull;
    if (current == null) {
      return const PostModerationApproveBlocked(
        'Aún cargamos la revisión. Espera un momento.',
      );
    }
    if (!current.isReady || current.review == null) {
      return const PostModerationApproveBlocked(
        'Esta publicación ya no está pendiente de aprobación.',
      );
    }
    if (current.approveForbidden) {
      return const PostModerationApproveBlocked(
        'No tienes autorización para moderar esta publicación.',
      );
    }
    if (_activeDecisionGeneration != null || current.approveInFlight) {
      return const PostModerationApproveInFlight();
    }
    if (current.approveUncertain) {
      return const PostModerationApproveBlocked(
        'Hay una decisión de moderación con resultado incierto. Consulta el '
        'estado actual antes de decidir de nuevo.',
      );
    }

    final pendingRevisionId = current.detail.pendingContent?.revisionId;
    if (pendingRevisionId == null) {
      return const PostModerationApproveBlocked(
        'No hay contenido pendiente confirmado para aprobar.',
      );
    }

    final epoch = neighborhoodSessionEpoch(ref);
    final userId = _authenticatedUserId();
    if (epoch == null || userId == null) {
      return const PostModerationApproveDiscarded();
    }

    if (userId == current.detail.author.id) {
      return const PostModerationApproveBlocked(
        'No puedes aprobar tu propia publicación.',
      );
    }

    final opGeneration = _approvePersistence.beginApproveAttempt(
      userId: userId,
      sessionEpoch: epoch,
      postId: arg.postId,
      pendingRevisionId: pendingRevisionId,
    );
    if (opGeneration == null) {
      if (_approvePersistence.peekRecordForPost(arg.postId) != null) {
        return const PostModerationApproveBlocked(
          'Hay otra decisión de moderación en curso o sin reconciliar.',
        );
      }
      return const PostModerationApproveBlocked(
        'No pudimos registrar la aprobación de forma segura.',
      );
    }

    final decisionGeneration = ++_decisionAttemptGeneration;
    _activeDecisionGeneration = decisionGeneration;
    state = AsyncValue.data(
      current.copyWith(approveInFlight: true, approveForbidden: false),
    );

    final keepAliveLink = ref.keepAlive();
    try {
      final updated = await ref
          .read(postRepositoryProvider)
          .approvePost(postId: arg.postId);

      if (!_decisionAttemptStillActive(
        operationGeneration: opGeneration,
        userId: userId,
        sessionEpoch: epoch,
        decisionGeneration: decisionGeneration,
      )) {
        _approvePersistence.promoteToOutcomeUncertainIfMatching(
          arg.postId,
          opGeneration,
        );
        return const PostModerationApproveDiscarded();
      }

      _approvePersistence.removeRecordIfMatching(arg.postId, opGeneration);
      final nextReview = PostModerationReviewState.fromDetail(
        detail: updated,
        expectedGroupId: arg.groupId,
      );
      state = AsyncValue.data(nextReview.copyWith(clearApproveFlags: true));
      _invalidateAfterConfirmedDecision();
      return const PostModerationApproveSuccess();
    } on ApiFailure catch (e) {
      if (!_decisionAttemptStillActive(
        operationGeneration: opGeneration,
        userId: userId,
        sessionEpoch: epoch,
        decisionGeneration: decisionGeneration,
      )) {
        return const PostModerationApproveDiscarded();
      }

      if (isModerationApproveOutcomeUncertain(e)) {
        _approvePersistence.promoteToOutcomeUncertainIfMatching(
          arg.postId,
          opGeneration,
        );
        state = AsyncValue.data(
          current.copyWith(approveInFlight: false, approveUncertain: true),
        );
        return const PostModerationApproveUncertain();
      }

      if (e is ApiForbiddenFailure) {
        _approvePersistence.removeRecordIfMatching(arg.postId, opGeneration);
        state = AsyncValue.data(
          current.copyWith(approveInFlight: false, approveForbidden: true),
        );
        return PostModerationApproveFailure(e);
      }

      if (e is ApiNotFoundFailure) {
        _approvePersistence.removeRecordIfMatching(arg.postId, opGeneration);
        state = AsyncValue.data(current.copyWith(approveInFlight: false));
        return PostModerationApproveFailure(e);
      }

      if (isPostModerationDomainFailure(e)) {
        _approvePersistence.removeRecordIfMatching(arg.postId, opGeneration);
        await refresh();
        ref.invalidate(postPendingQueueControllerProvider(arg.groupId));
        return PostModerationApproveFailure(e);
      }

      _approvePersistence.removeRecordIfMatching(arg.postId, opGeneration);
      state = AsyncValue.data(current.copyWith(approveInFlight: false));
      return PostModerationApproveFailure(e);
    } catch (_) {
      if (!_decisionAttemptStillActive(
        operationGeneration: opGeneration,
        userId: userId,
        sessionEpoch: epoch,
        decisionGeneration: decisionGeneration,
      )) {
        return const PostModerationApproveDiscarded();
      }
      _approvePersistence.promoteToOutcomeUncertainIfMatching(
        arg.postId,
        opGeneration,
      );
      state = AsyncValue.data(
        current.copyWith(approveInFlight: false, approveUncertain: true),
      );
      return const PostModerationApproveUncertain();
    } finally {
      keepAliveLink.close();
      if (_activeDecisionGeneration == decisionGeneration) {
        _activeDecisionGeneration = null;
      }
      final value = state.valueOrNull;
      if (value != null && value.approveInFlight) {
        state = AsyncValue.data(value.copyWith(approveInFlight: false));
      }
    }
  }

  Future<PostModerationApproveReconcileResult>
  reconcileUncertainApprove() async {
    final current = state.valueOrNull;
    if (current == null || !current.approveUncertain) {
      return const PostModerationApproveReconcileStillUncertain(
        'No hay una decisión de moderación incierta que verificar.',
      );
    }
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return const PostModerationApproveReconcileDiscarded();
    }

    final record = _approvePersistence.recordFor(arg.postId);
    final generation = ++_loadGeneration;

    try {
      final remote = await ref.read(postRepositoryProvider).getPost(arg.postId);
      if (generation != _loadGeneration ||
          neighborhoodSessionEpoch(ref) != epoch) {
        return const PostModerationApproveReconcileDiscarded();
      }

      final classified = PostModerationReviewState.fromDetail(
        detail: remote,
        expectedGroupId: arg.groupId,
      );

      if (classified.isReady) {
        if (record != null) {
          _approvePersistence.removeRecordIfMatching(
            arg.postId,
            record.operationGeneration,
          );
        }
        state = AsyncValue.data(
          classified.copyWith(approveUncertain: false, approveInFlight: false),
        );
        ref.invalidate(postPendingQueueControllerProvider(arg.groupId));
        return const PostModerationApproveReconcileStillPending(
          'El servidor aún muestra esta revisión como pendiente. '
          'Eso no confirma si tu decisión anterior tuvo efecto. '
          'Puedes decidir de nuevo con confirmación explícita.',
        );
      }

      if (record != null) {
        _approvePersistence.removeRecordIfMatching(
          arg.postId,
          record.operationGeneration,
        );
      }
      state = AsyncValue.data(
        classified.copyWith(approveUncertain: false, approveInFlight: false),
      );
      ref.invalidate(postPendingQueueControllerProvider(arg.groupId));
      ref.invalidate(feedControllerProvider);
      return const PostModerationApproveReconcileResolved(
        'El estado observado ya no está pendiente de moderación. '
        'No atribuimos el cambio a una decisión anterior sin respuesta '
        'confirmada.',
      );
    } on ApiFailure catch (e) {
      return PostModerationApproveReconcileGetFailed(e);
    }
  }

  Future<PostModerationRejectResult> rejectPublication(
    String rejectionReason,
  ) async {
    final validation = validatePostRejectionReason(rejectionReason);
    if (validation != null) {
      return PostModerationRejectValidationFailure(validation);
    }

    final current = state.valueOrNull;
    if (current == null) {
      return const PostModerationRejectBlocked(
        'Aún cargamos la revisión. Espera un momento.',
      );
    }
    if (!current.isReady || current.review == null) {
      return const PostModerationRejectBlocked(
        'Esta publicación ya no está pendiente de rechazo.',
      );
    }
    if (current.approveForbidden) {
      return const PostModerationRejectBlocked(
        'No tienes autorización para moderar esta publicación.',
      );
    }
    if (_activeDecisionGeneration != null || current.approveInFlight) {
      return const PostModerationRejectInFlight();
    }
    if (current.approveUncertain) {
      return const PostModerationRejectBlocked(
        'Hay una decisión de moderación con resultado incierto. Consulta el '
        'estado actual antes de decidir de nuevo.',
      );
    }

    final pendingRevisionId = current.detail.pendingContent?.revisionId;
    if (pendingRevisionId == null) {
      return const PostModerationRejectBlocked(
        'No hay contenido pendiente confirmado para rechazar.',
      );
    }

    final epoch = neighborhoodSessionEpoch(ref);
    final userId = _authenticatedUserId();
    if (epoch == null || userId == null) {
      return const PostModerationRejectDiscarded();
    }

    if (userId == current.detail.author.id) {
      return const PostModerationRejectBlocked(
        'No puedes rechazar tu propia publicación.',
      );
    }

    final opGeneration = _approvePersistence.beginDecisionAttempt(
      userId: userId,
      sessionEpoch: epoch,
      postId: arg.postId,
      pendingRevisionId: pendingRevisionId,
      decisionKind: PostModerationDecisionKind.reject,
    );
    if (opGeneration == null) {
      return const PostModerationRejectBlocked(
        'Hay otra decisión de moderación en curso o sin reconciliar.',
      );
    }

    final decisionGeneration = ++_decisionAttemptGeneration;
    _activeDecisionGeneration = decisionGeneration;
    state = AsyncValue.data(
      current.copyWith(approveInFlight: true, approveForbidden: false),
    );

    final keepAliveLink = ref.keepAlive();
    try {
      final updated = await ref
          .read(postRepositoryProvider)
          .rejectPost(postId: arg.postId, rejectionReason: rejectionReason);

      if (!_decisionAttemptStillActive(
        operationGeneration: opGeneration,
        userId: userId,
        sessionEpoch: epoch,
        decisionGeneration: decisionGeneration,
      )) {
        _approvePersistence.promoteToOutcomeUncertainIfMatching(
          arg.postId,
          opGeneration,
        );
        return const PostModerationRejectDiscarded();
      }

      _approvePersistence.removeRecordIfMatching(arg.postId, opGeneration);
      final nextReview = PostModerationReviewState.fromDetail(
        detail: updated,
        expectedGroupId: arg.groupId,
      );
      state = AsyncValue.data(nextReview.copyWith(clearApproveFlags: true));
      _invalidateAfterConfirmedDecision();
      return const PostModerationRejectSuccess();
    } on ApiFailure catch (e) {
      if (!_decisionAttemptStillActive(
        operationGeneration: opGeneration,
        userId: userId,
        sessionEpoch: epoch,
        decisionGeneration: decisionGeneration,
      )) {
        return const PostModerationRejectDiscarded();
      }

      if (e is ApiValidationFailure && e.fieldErrors.isNotEmpty) {
        _approvePersistence.removeRecordIfMatching(arg.postId, opGeneration);
        state = AsyncValue.data(current.copyWith(approveInFlight: false));
        return PostModerationRejectFailure(e);
      }

      if (isModerationDecisionOutcomeUncertain(e)) {
        _approvePersistence.promoteToOutcomeUncertainIfMatching(
          arg.postId,
          opGeneration,
        );
        state = AsyncValue.data(
          current.copyWith(approveInFlight: false, approveUncertain: true),
        );
        return const PostModerationRejectUncertain();
      }

      if (e is ApiForbiddenFailure) {
        _approvePersistence.removeRecordIfMatching(arg.postId, opGeneration);
        state = AsyncValue.data(
          current.copyWith(approveInFlight: false, approveForbidden: true),
        );
        return PostModerationRejectFailure(e);
      }

      if (e is ApiNotFoundFailure) {
        _approvePersistence.removeRecordIfMatching(arg.postId, opGeneration);
        state = AsyncValue.data(current.copyWith(approveInFlight: false));
        return PostModerationRejectFailure(e);
      }

      if (isPostModerationDomainFailure(e)) {
        _approvePersistence.removeRecordIfMatching(arg.postId, opGeneration);
        await refresh();
        ref.invalidate(postPendingQueueControllerProvider(arg.groupId));
        return PostModerationRejectFailure(e);
      }

      _approvePersistence.removeRecordIfMatching(arg.postId, opGeneration);
      state = AsyncValue.data(current.copyWith(approveInFlight: false));
      return PostModerationRejectFailure(e);
    } catch (_) {
      if (!_decisionAttemptStillActive(
        operationGeneration: opGeneration,
        userId: userId,
        sessionEpoch: epoch,
        decisionGeneration: decisionGeneration,
      )) {
        return const PostModerationRejectDiscarded();
      }
      _approvePersistence.promoteToOutcomeUncertainIfMatching(
        arg.postId,
        opGeneration,
      );
      state = AsyncValue.data(
        current.copyWith(approveInFlight: false, approveUncertain: true),
      );
      return const PostModerationRejectUncertain();
    } finally {
      keepAliveLink.close();
      if (_activeDecisionGeneration == decisionGeneration) {
        _activeDecisionGeneration = null;
      }
      final value = state.valueOrNull;
      if (value != null && value.approveInFlight) {
        state = AsyncValue.data(value.copyWith(approveInFlight: false));
      }
    }
  }

  void _invalidateAfterConfirmedDecision() {
    ref.invalidate(postPendingQueueControllerProvider(arg.groupId));
    ref.invalidate(feedControllerProvider);
    ref.invalidate(postDetailControllerProvider(arg.postId));
  }
}

final postModerationReviewControllerProvider =
    AutoDisposeAsyncNotifierProvider.family<
      PostModerationReviewController,
      PostModerationReviewState,
      PostModerationReviewKey
    >(PostModerationReviewController.new);
