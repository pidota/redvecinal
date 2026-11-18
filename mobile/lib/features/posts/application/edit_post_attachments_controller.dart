import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import '../data/models/post_detail.dart';
import '../data/post_repository.dart';
import '../support/post_attachment_picker_validation.dart';
import '../support/post_attachment_slot_counter.dart';
import 'create_post_file_picker.dart';
import 'create_post_local_attachment.dart';
import 'create_post_uncertain_upload_record.dart';
import 'edit_post_attachment_upload_support.dart';
import 'edit_post_attachments_persistence.dart';
import 'edit_post_exclusive_operation.dart';
import 'edit_post_uncertain_patch_persistence.dart';
import 'edit_post_uncertain_upload_record.dart';

class EditPostAttachmentsState {
  const EditPostAttachmentsState({
    this.postId = 0,
    this.revisionId,
    this.serverAttachments = const [],
    this.serverAttachmentIds = const [],
    this.localItems = const [],
    this.bannerMessage,
    this.uploadInFlight = false,
    this.reconcileInFlight = false,
    this.revisionSyncInFlight = false,
  });

  final int postId;
  final int? revisionId;
  final List<PostAttachment> serverAttachments;
  final List<int> serverAttachmentIds;
  final List<CreatePostLocalAttachment> localItems;
  final String? bannerMessage;
  final bool uploadInFlight;
  final bool reconcileInFlight;
  final bool revisionSyncInFlight;

  bool get hasBlockingUncertain =>
      localItems.any((e) => e.state == CreatePostAttachmentState.uncertain);

  bool get hasUploading =>
      localItems.any((e) => e.state == CreatePostAttachmentState.uploading) ||
      uploadInFlight;

  bool get blocksContentSave => hasBlockingUncertain || hasUploading;

  int remainingSlots(List<EditPostUncertainUploadRecord> uncertainRecords) {
    final mapped =
        uncertainRecords
            .map(
              (e) => CreatePostUncertainUploadRecord(
                clientId: e.clientId,
                displayName: e.displayName,
                sizeBytes: e.sizeBytes,
                mimeType: e.mimeType,
                localPath: e.localPath,
              ),
            )
            .toList();
    return PostAttachmentSlotCounter.remainingSlots(
      serverAttachmentIds: serverAttachmentIds,
      localItems: localItems,
      uncertainRecords: mapped,
    );
  }

  bool canAddMore({
    required bool patchBlocks,
    required List<EditPostUncertainUploadRecord> uncertainRecords,
  }) {
    return !patchBlocks &&
        !hasBlockingUncertain &&
        !hasUploading &&
        !revisionSyncInFlight &&
        revisionId != null &&
        remainingSlots(uncertainRecords) > 0;
  }

  List<CreatePostLocalAttachment> get needsUpload =>
      localItems
          .where(
            (e) =>
                e.state == CreatePostAttachmentState.selected ||
                e.state == CreatePostAttachmentState.failed,
          )
          .toList();

  EditPostAttachmentsState copyWith({
    int? postId,
    int? revisionId,
    List<PostAttachment>? serverAttachments,
    List<int>? serverAttachmentIds,
    List<CreatePostLocalAttachment>? localItems,
    String? bannerMessage,
    bool? uploadInFlight,
    bool? reconcileInFlight,
    bool? revisionSyncInFlight,
    bool clearBanner = false,
  }) {
    return EditPostAttachmentsState(
      postId: postId ?? this.postId,
      revisionId: revisionId ?? this.revisionId,
      serverAttachments: serverAttachments ?? this.serverAttachments,
      serverAttachmentIds: serverAttachmentIds ?? this.serverAttachmentIds,
      localItems: localItems ?? this.localItems,
      bannerMessage: clearBanner ? null : (bannerMessage ?? this.bannerMessage),
      uploadInFlight: uploadInFlight ?? this.uploadInFlight,
      reconcileInFlight: reconcileInFlight ?? this.reconcileInFlight,
      revisionSyncInFlight: revisionSyncInFlight ?? this.revisionSyncInFlight,
    );
  }
}

sealed class EditPostUploadOutcome {}

class EditPostUploadIdle extends EditPostUploadOutcome {}

class EditPostUploadSuccess extends EditPostUploadOutcome {}

class EditPostUploadFailure extends EditPostUploadOutcome {
  EditPostUploadFailure(this.message);
  final String message;
}

class EditPostUploadUncertain extends EditPostUploadOutcome {}

class EditPostUploadBlocked extends EditPostUploadOutcome {
  EditPostUploadBlocked(this.message);
  final String message;
}

class EditPostUploadDiscarded extends EditPostUploadOutcome {}

class EditPostUploadReconcileInconclusive extends EditPostUploadOutcome {}

class EditPostAttachmentsController
    extends AutoDisposeFamilyNotifier<EditPostAttachmentsState, int> {
  EditPostAttachmentsState _held = const EditPostAttachmentsState();
  int _uploadGeneration = 0;
  CancelToken? _cancelToken;
  EditPostAttachmentsPersistence? _persistence;
  EditPostUncertainPatchPersistence? _patchPersistence;
  CreatePostFilePickerPort? _filePicker;
  PostGateway? _repository;
  int? _boundUserId;
  int? _boundEpoch;
  int _lastAppliedEditorLoadGeneration = 0;
  int? _authoritativeRevisionId;

  EditPostAttachmentsPersistence get _persistenceOrThrow => _persistence!;

  @override
  EditPostAttachmentsState build(int postId) {
    ref.watch(authControllerProvider);
    ref.watch(editPostAttachmentsPersistenceProvider);
    _persistence = ref.read(editPostAttachmentsPersistenceProvider.notifier);
    _patchPersistence = ref.read(
      editPostUncertainPatchPersistenceProvider.notifier,
    );
    _filePicker = ref.read(createPostFilePickerProvider);
    _repository = ref.read(postRepositoryProvider);
    final auth = ref.read(authControllerProvider);
    _boundUserId = auth is AuthAuthenticated ? auth.user.id : null;
    _boundEpoch = neighborhoodSessionEpoch(ref);
    final record = _persistence!.peekRecordForPost(postId);
    if (record != null && record.hasUnresolvedUncertain) {
      _held = _restoreUncertain(_held, record);
    }
    _held = _held.copyWith(postId: postId);
    return _held;
  }

  void hydrateFromEditableRevision({
    required int revisionId,
    required List<PostAttachment> serverAttachments,
    int editorLoadGeneration = 1,
  }) {
    syncFromEditorSnapshot(
      editorLoadGeneration: editorLoadGeneration,
      editable: true,
      editableRevisionId: revisionId,
      serverAttachments: serverAttachments,
    );
  }

  /// Sincroniza adjuntos tras cada GET exitoso del editor (incluye pull-to-refresh).
  void syncFromEditorSnapshot({
    required int editorLoadGeneration,
    required bool editable,
    required int? editableRevisionId,
    required List<PostAttachment> serverAttachments,
    String? blockMessage,
  }) {
    if (editorLoadGeneration < _lastAppliedEditorLoadGeneration) {
      return;
    }
    _lastAppliedEditorLoadGeneration = editorLoadGeneration;

    final userId = _boundUserId;
    final epoch = _boundEpoch;
    if (userId == null || epoch == null) {
      return;
    }

    _publish(_held.copyWith(revisionSyncInFlight: true));

    final oldRevision = _held.revisionId;
    final revisionChanged =
        editableRevisionId != null &&
        oldRevision != null &&
        oldRevision != editableRevisionId;

    String? banner = blockMessage;
    if (revisionChanged) {
      banner =
          banner ??
          'La revisión editable cambió en el servidor. Los archivos que '
              'habías seleccionado ya no aplican; elige de nuevo si aún quieres subirlos.';
    }

    final preservedLocals = <CreatePostLocalAttachment>[];
    for (final item in _held.localItems) {
      switch (item.state) {
        case CreatePostAttachmentState.uncertain:
        case CreatePostAttachmentState.uploading:
        case CreatePostAttachmentState.uploaded:
          preservedLocals.add(item);
        case CreatePostAttachmentState.selected:
        case CreatePostAttachmentState.failed:
          if (!revisionChanged && editable && editableRevisionId != null) {
            preservedLocals.add(item);
          }
      }
    }

    if (!editable || editableRevisionId == null) {
      _authoritativeRevisionId = null;
      _publish(
        EditPostAttachmentsState(
          postId: arg,
          revisionId: null,
          serverAttachments: const [],
          serverAttachmentIds: const [],
          localItems:
              preservedLocals
                  .where(
                    (e) =>
                        e.state == CreatePostAttachmentState.uncertain ||
                        e.state == CreatePostAttachmentState.uploading,
                  )
                  .toList(),
          bannerMessage: banner,
          uploadInFlight: _held.uploadInFlight,
          revisionSyncInFlight: false,
        ),
      );
      return;
    }

    final ids = serverAttachments.map((a) => a.id).toList();
    _persistenceOrThrow.syncServerAttachments(
      userId: userId,
      sessionEpoch: epoch,
      postId: arg,
      revisionId: editableRevisionId,
      attachmentIds: ids,
    );
    _authoritativeRevisionId = editableRevisionId;

    _publish(
      _held.copyWith(
        postId: arg,
        revisionId: editableRevisionId,
        serverAttachments: serverAttachments,
        serverAttachmentIds: ids,
        localItems: preservedLocals,
        bannerMessage: banner,
        revisionSyncInFlight: false,
        clearBanner: banner == null,
      ),
    );
  }

  void _publish(EditPostAttachmentsState next) {
    _held = next;
    state = next;
  }

  void _syncFromEditableRevision(
    int postId, {
    required int revisionId,
    required List<PostAttachment> serverAttachments,
  }) {
    final userId = _boundUserId;
    final epoch = _boundEpoch;
    if (userId == null || epoch == null) {
      return;
    }
    final server = serverAttachments;
    final ids = server.map((a) => a.id).toList();
    _persistenceOrThrow.syncServerAttachments(
      userId: userId,
      sessionEpoch: epoch,
      postId: postId,
      revisionId: revisionId,
      attachmentIds: ids,
    );
    if (_held.revisionId != null && _held.revisionId != revisionId) {
      _publish(
        EditPostAttachmentsState(
          postId: postId,
          revisionId: revisionId,
          serverAttachments: server,
          serverAttachmentIds: ids,
        ),
      );
      return;
    }
    _publish(
      _held.copyWith(
        postId: postId,
        revisionId: revisionId,
        serverAttachments: server,
        serverAttachmentIds: ids,
        clearBanner: true,
      ),
    );
  }

  EditPostAttachmentsState _restoreUncertain(
    EditPostAttachmentsState base,
    EditPostAttachmentPersistenceRecord record,
  ) {
    if (base.localItems.isNotEmpty) {
      return base;
    }
    final restored =
        record.uncertainUploads.map((record) {
          return CreatePostLocalAttachment(
            clientId: record.clientId,
            path: record.localPath ?? '',
            displayName: record.displayName,
            sizeBytes: record.sizeBytes,
            mimeType: record.mimeType,
            state: CreatePostAttachmentState.uncertain,
            userMessage: editPostUncertainUploadBlockedMessage,
          );
        }).toList();
    return base.copyWith(
      revisionId: record.revisionId,
      serverAttachmentIds: record.serverAttachmentIds,
      localItems: restored,
    );
  }

  bool _patchBlocksUpload() {
    if (_held.revisionSyncInFlight) {
      return true;
    }
    final attachPersistence = _persistence;
    final patchPersistence = _patchPersistence;
    if (attachPersistence == null || patchPersistence == null) {
      return true;
    }
    if (attachPersistence.blocksUploadForPost(arg)) {
      return true;
    }
    return patchPersistence.peekRecordForPost(arg) != null;
  }

  bool _sessionAndRevisionStillValid({
    required int? userId,
    required int? epoch,
    required int? revisionBefore,
  }) {
    if (userId != _boundUserId || epoch != _boundEpoch) {
      return false;
    }
    if (!_persistenceOrThrow.sessionBindingActiveFor(userId!, epoch!)) {
      return false;
    }
    if (_held.revisionSyncInFlight) {
      return false;
    }
    if (_patchBlocksUpload()) {
      return false;
    }
    if (revisionBefore != _held.revisionId) {
      return false;
    }
    final authoritative = _authoritativeRevisionId;
    if (authoritative != null && revisionBefore != authoritative) {
      return false;
    }
    return _held.revisionId != null;
  }

  String? validatePickedFile(PickedPostFile file) {
    final record = _persistenceOrThrow.peekRecordForPost(arg);
    final uncertain = record?.uncertainUploads ?? const [];
    final remaining = _held.remainingSlots(uncertain);
    return validatePickedPostAttachmentFile(file, remainingSlots: remaining);
  }

  Future<String?> pickAndAddImage() async {
    if (!_held.canAddMore(
      patchBlocks: _patchBlocksUpload(),
      uncertainRecords:
          _persistenceOrThrow.peekRecordForPost(arg)?.uncertainUploads ??
          const [],
    )) {
      return 'No puedes agregar archivos en este momento.';
    }
    final userBefore = _boundUserId;
    final epochBefore = _boundEpoch;
    final revisionBefore = _held.revisionId;
    final picked = await _filePicker?.pickImage();
    if (picked == null) {
      return null;
    }
    if (!_sessionAndRevisionStillValid(
      userId: userBefore,
      epoch: epochBefore,
      revisionBefore: revisionBefore,
    )) {
      return 'La sesión o la revisión cambió. Vuelve a elegir el archivo.';
    }
    final error = validatePickedFile(picked);
    if (error != null) {
      _publish(_held.copyWith(bannerMessage: error));
      return error;
    }
    _addPicked(picked);
    return null;
  }

  Future<String?> pickAndAddPdf() async {
    if (!_held.canAddMore(
      patchBlocks: _patchBlocksUpload(),
      uncertainRecords:
          _persistenceOrThrow.peekRecordForPost(arg)?.uncertainUploads ??
          const [],
    )) {
      return 'No puedes agregar archivos en este momento.';
    }
    final userBefore = _boundUserId;
    final epochBefore = _boundEpoch;
    final revisionBefore = _held.revisionId;
    final picked = await _filePicker?.pickPdf();
    if (picked == null) {
      return null;
    }
    if (!_sessionAndRevisionStillValid(
      userId: userBefore,
      epoch: epochBefore,
      revisionBefore: revisionBefore,
    )) {
      return 'La sesión o la revisión cambió. Vuelve a elegir el archivo.';
    }
    final error = validatePickedFile(picked);
    if (error != null) {
      _publish(_held.copyWith(bannerMessage: error));
      return error;
    }
    _addPicked(picked);
    return null;
  }

  void _addPicked(PickedPostFile picked) {
    _publish(
      _held.copyWith(
        localItems: [
          ..._held.localItems,
          CreatePostLocalAttachment(
            clientId: CreatePostLocalAttachment.newClientId(),
            path: picked.path,
            displayName: picked.displayName,
            sizeBytes: picked.sizeBytes,
            mimeType: picked.mimeType,
          ),
        ],
        clearBanner: true,
      ),
    );
  }

  void removeLocalSelected(String clientId) {
    CreatePostLocalAttachment? item;
    for (final e in _held.localItems) {
      if (e.clientId == clientId) {
        item = e;
        break;
      }
    }
    if (item == null || !item.canRemoveLocally) {
      return;
    }
    _publish(
      _held.copyWith(
        localItems:
            _held.localItems.where((e) => e.clientId != clientId).toList(),
      ),
    );
  }

  void applyItemUpdate(CreatePostLocalAttachment updated) {
    _publish(
      _held.copyWith(
        localItems:
            _held.localItems
                .map((e) => e.clientId == updated.clientId ? updated : e)
                .toList(),
      ),
    );
  }

  Future<EditPostUploadOutcome> uploadPending() async {
    final userId = _boundUserId;
    final epoch = _boundEpoch;
    if (userId == null || epoch == null) {
      return EditPostUploadDiscarded();
    }

    final persistence = _persistenceOrThrow;
    final lease = persistence.tryAcquireExclusive(
      userId: userId,
      sessionEpoch: epoch,
      postId: arg,
      kind: EditPostExclusiveOperationKind.upload,
    );
    if (lease == null) {
      return EditPostUploadBlocked(
        'Hay otra operación en curso. Espera a que termine.',
      );
    }

    if (_held.uploadInFlight || _held.reconcileInFlight) {
      persistence.releaseExclusive(lease);
      return EditPostUploadBlocked('Ya hay una subida en curso.');
    }
    if (_patchBlocksUpload()) {
      persistence.releaseExclusive(lease);
      return EditPostUploadBlocked(
        'Hay un guardado incierto o en curso. Resuélvelo antes de subir archivos.',
      );
    }

    final revisionId = _held.revisionId;
    final authoritative = _authoritativeRevisionId;
    if (revisionId == null) {
      persistence.releaseExclusive(lease);
      return EditPostUploadBlocked('No hay una revisión editable.');
    }
    if (authoritative != null && revisionId != authoritative) {
      persistence.releaseExclusive(lease);
      return EditPostUploadBlocked(
        'La revisión editable cambió. Actualiza la pantalla antes de subir.',
      );
    }
    final uploadRevisionId = revisionId;

    final record = persistence.peekRecordForPost(arg);
    final uncertainIds =
        record?.uncertainUploads.map((e) => e.clientId).toSet() ?? {};
    final pending =
        _held.needsUpload
            .where((e) => !uncertainIds.contains(e.clientId))
            .toList();
    if (pending.isEmpty) {
      persistence.releaseExclusive(lease);
      return EditPostUploadIdle();
    }

    final uploadGeneration = ++_uploadGeneration;
    _cancelToken?.cancel();
    _cancelToken = CancelToken();
    _publish(_held.copyWith(uploadInFlight: true, clearBanner: true));

    try {
      for (final item in pending) {
        if (!_stillBound(userId, epoch, uploadGeneration, persistence)) {
          return EditPostUploadDiscarded();
        }
        if (!File(item.path).existsSync()) {
          applyItemUpdate(
            item.copyWith(
              state: CreatePostAttachmentState.failed,
              userMessage:
                  'El archivo ya no está disponible. Selecciónalo de nuevo.',
            ),
          );
          return EditPostUploadFailure(
            'Un archivo local ya no está disponible.',
          );
        }

        applyItemUpdate(
          item.copyWith(
            state: CreatePostAttachmentState.uploading,
            uploadProgress: 0,
            clearUserMessage: true,
          ),
        );

        try {
          final result = await _repository!.uploadPostAttachment(
            postId: arg,
            revisionId: uploadRevisionId,
            filePath: item.path,
            filename: item.displayName,
            mimeType: item.mimeType,
            cancelToken: _cancelToken,
            onSendProgress: (sent, total) {
              if (total > 0) {
                applyItemUpdate(
                  item.copyWith(
                    state: CreatePostAttachmentState.uploading,
                    uploadProgress: sent / total,
                  ),
                );
              }
            },
          );

          if (!_stillBound(userId, epoch, uploadGeneration, persistence)) {
            return EditPostUploadDiscarded();
          }

          persistence.recordUploadedAttachment(
            postId: arg,
            attachmentId: result.id,
          );
          persistence.resolveUncertainUpload(
            postId: arg,
            clientId: item.clientId,
          );

          final serverAttach = PostAttachment(
            id: result.id,
            revisionId: result.revisionId,
            originalDisplayName: result.originalDisplayName,
            mimeType: result.mimeType,
            sizeBytes: result.sizeBytes,
            downloadUrl: '/api/v1/posts/$arg/attachments/${result.id}',
          );

          _publish(
            _held.copyWith(
              serverAttachmentIds: [..._held.serverAttachmentIds, result.id],
              serverAttachments: [..._held.serverAttachments, serverAttach],
            ),
          );

          applyItemUpdate(
            item.copyWith(
              state: CreatePostAttachmentState.uploaded,
              serverAttachmentId: result.id,
              clearProgress: true,
            ),
          );
        } on ApiFailure catch (e) {
          if (!_stillBound(userId, epoch, uploadGeneration, persistence)) {
            return EditPostUploadDiscarded();
          }
          if (isEditPostUploadOutcomeUncertain(e)) {
            _registerUncertain(
              persistence,
              userId: userId,
              epoch: epoch,
              revisionId: uploadRevisionId,
              item: item,
            );
            applyItemUpdate(
              item.copyWith(
                state: CreatePostAttachmentState.uncertain,
                userMessage: editPostUncertainUploadBlockedMessage,
                clearProgress: true,
              ),
            );
            return EditPostUploadUncertain();
          }
          applyItemUpdate(
            item.copyWith(
              state: CreatePostAttachmentState.failed,
              userMessage: e.userMessage,
              clearProgress: true,
            ),
          );
          return EditPostUploadFailure(e.userMessage);
        } catch (_) {
          if (!_stillBound(userId, epoch, uploadGeneration, persistence)) {
            return EditPostUploadDiscarded();
          }
          _registerUncertain(
            persistence,
            userId: userId,
            epoch: epoch,
            revisionId: uploadRevisionId,
            item: item,
          );
          applyItemUpdate(
            item.copyWith(
              state: CreatePostAttachmentState.uncertain,
              userMessage: editPostUncertainUploadBlockedMessage,
              clearProgress: true,
            ),
          );
          return EditPostUploadUncertain();
        }
      }
      return EditPostUploadSuccess();
    } finally {
      persistence.releaseExclusive(lease);
      if (uploadGeneration == _uploadGeneration) {
        _publish(_held.copyWith(uploadInFlight: false));
        _cancelToken = null;
      }
    }
  }

  void _registerUncertain(
    EditPostAttachmentsPersistence persistence, {
    required int userId,
    required int epoch,
    required int revisionId,
    required CreatePostLocalAttachment item,
  }) {
    persistence.registerUncertainUpload(
      EditPostUncertainUploadRecord(
        postId: arg,
        revisionId: revisionId,
        userId: userId,
        sessionEpoch: epoch,
        clientId: item.clientId,
        displayName: item.displayName,
        sizeBytes: item.sizeBytes,
        mimeType: item.mimeType,
        localPath: item.path,
      ),
    );
  }

  bool _stillBound(
    int userId,
    int epoch,
    int uploadGeneration,
    EditPostAttachmentsPersistence persistence,
  ) {
    if (uploadGeneration != _uploadGeneration) {
      return false;
    }
    return persistence.sessionBindingActiveFor(userId, epoch);
  }

  Future<EditPostUploadOutcome> reconcileUploadsFromServer() async {
    if (_held.uploadInFlight || _held.reconcileInFlight) {
      return EditPostUploadBlocked('Hay una operación en curso.');
    }
    final userId = _boundUserId;
    final epoch = _boundEpoch;
    if (userId == null || epoch == null) {
      return EditPostUploadDiscarded();
    }
    final persistence = _persistenceOrThrow;
    final record = persistence.peekRecordForPost(arg);
    if (record == null || !record.hasUnresolvedUncertain) {
      return EditPostUploadBlocked('No hay subidas inciertas.');
    }

    _publish(_held.copyWith(reconcileInFlight: true));
    try {
      final detail = await _repository!.getPost(arg);
      if (!persistence.sessionBindingActiveFor(userId, epoch)) {
        return EditPostUploadDiscarded();
      }
      if (detail.status != 'draft' && detail.status != 'rejected') {
        return EditPostUploadBlocked(
          'El servidor cambió el estado y ya no admite adjuntos.',
        );
      }
      final revisionId = detail.editableRevisionId;
      if (revisionId == null) {
        return EditPostUploadFailure('No pudimos leer la revisión editable.');
      }
      final idsForRevision =
          detail.attachments
              .where((a) => a.revisionId == revisionId)
              .map((a) => a.id)
              .toList();
      persistence.syncServerAttachments(
        userId: userId,
        sessionEpoch: epoch,
        postId: arg,
        revisionId: revisionId,
        attachmentIds: idsForRevision,
      );
      final stillUncertain =
          persistence.peekRecordForPost(arg)?.hasUnresolvedUncertain ?? false;
      final editable =
          detail.attachments.where((a) => a.revisionId == revisionId).toList();
      _syncFromEditableRevision(
        arg,
        revisionId: revisionId,
        serverAttachments: editable,
      );
      if (stillUncertain) {
        _publish(
          _held.copyWith(
            bannerMessage: editPostUploadReconcileInconclusiveMessage,
          ),
        );
        return EditPostUploadReconcileInconclusive();
      }
      return EditPostUploadSuccess();
    } on ApiFailure catch (e) {
      return EditPostUploadFailure(e.userMessage);
    } finally {
      _publish(_held.copyWith(reconcileInFlight: false));
    }
  }

  @visibleForTesting
  void setLocalItemsForTests(List<CreatePostLocalAttachment> items) {
    _publish(_held.copyWith(localItems: items));
  }
}

final editPostAttachmentsControllerProvider = NotifierProvider.autoDispose
    .family<EditPostAttachmentsController, EditPostAttachmentsState, int>(
      EditPostAttachmentsController.new,
    );
