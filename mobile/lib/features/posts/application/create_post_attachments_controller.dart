import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/models/post_detail.dart';
import '../support/post_attachment_limits.dart';
import '../support/post_attachment_slot_counter.dart';
import 'create_post_file_picker.dart';
import 'create_post_local_attachment.dart';
import 'create_post_session_persistence.dart';

const uncertainUploadBlockedMessage =
    'No pudimos confirmar si el archivo se guardó. Para evitar duplicados, '
    'no es posible reenviarlo automáticamente ni continuar con el envío a revisión.';

const _reconcileInconclusiveMessage =
    'Consultamos el servidor, pero la API no permite confirmar automáticamente '
    'si una subida incierta tuvo éxito. Solo una respuesta HTTP 201 en esta '
    'sesión confirma un archivo. El envío sigue pausado hasta resolver manualmente.';

class CreatePostAttachmentsState {
  const CreatePostAttachmentsState({
    this.items = const [],
    this.serverAttachmentIds = const [],
    this.bannerMessage,
  });

  final List<CreatePostLocalAttachment> items;
  final List<int> serverAttachmentIds;
  final String? bannerMessage;

  int remainingSlots(CreatePostSessionPersistenceState session) {
    return PostAttachmentSlotCounter.remainingSlots(
      serverAttachmentIds:
          serverAttachmentIds.isNotEmpty
              ? serverAttachmentIds
              : session.serverAttachmentIds,
      localItems: items,
      uncertainRecords: session.uncertainUploadRecords,
    );
  }

  bool hasBlockingUncertain(CreatePostSessionPersistenceState session) {
    return items.any((e) => e.state == CreatePostAttachmentState.uncertain) ||
        session.hasUnresolvedUncertainUpload;
  }

  bool get hasUploading =>
      items.any((e) => e.state == CreatePostAttachmentState.uploading);

  bool canAddMore(CreatePostSessionPersistenceState session) =>
      remainingSlots(session) > 0 &&
      !hasBlockingUncertain(session) &&
      !session.linkedDraftPending;

  List<CreatePostLocalAttachment> get needsUpload =>
      items
          .where(
            (e) =>
                e.state == CreatePostAttachmentState.selected ||
                e.state == CreatePostAttachmentState.failed,
          )
          .toList();

  CreatePostAttachmentsState copyWith({
    List<CreatePostLocalAttachment>? items,
    List<int>? serverAttachmentIds,
    String? bannerMessage,
    bool clearBanner = false,
  }) {
    return CreatePostAttachmentsState(
      items: items ?? this.items,
      serverAttachmentIds: serverAttachmentIds ?? this.serverAttachmentIds,
      bannerMessage: clearBanner ? null : (bannerMessage ?? this.bannerMessage),
    );
  }
}

class CreatePostAttachmentsController
    extends AutoDisposeNotifier<CreatePostAttachmentsState> {
  int? _trackedEpoch;
  CreatePostAttachmentsState _held = const CreatePostAttachmentsState();

  CreatePostSessionPersistenceState get _session =>
      ref.read(createPostSessionPersistenceProvider);

  void _publish(CreatePostAttachmentsState next) {
    _held = next;
    state = next;
  }

  @override
  CreatePostAttachmentsState build() {
    ref.watch(authControllerProvider);
    final session = ref.watch(createPostSessionPersistenceProvider);
    final epoch = ref.watch(createPostSessionEpochProvider);
    if (epoch == null) {
      _trackedEpoch = null;
      _held = const CreatePostAttachmentsState();
      return _held;
    }
    if (_trackedEpoch != epoch) {
      _trackedEpoch = epoch;
      _held = CreatePostAttachmentsState(
        serverAttachmentIds: session.serverAttachmentIds,
      );
      if (session.uncertainUploadRecords.isNotEmpty) {
        _held = _restoreUncertainPlaceholders(_held, session);
      }
      return _held;
    }

    var next = _held.copyWith(
      serverAttachmentIds:
          _held.serverAttachmentIds.isEmpty
              ? session.serverAttachmentIds
              : _held.serverAttachmentIds,
    );
    if (next.items.isEmpty && session.uncertainUploadRecords.isNotEmpty) {
      next = _restoreUncertainPlaceholders(next, session);
    }
    _held = next;
    return _held;
  }

  CreatePostAttachmentsState _restoreUncertainPlaceholders(
    CreatePostAttachmentsState base,
    CreatePostSessionPersistenceState session,
  ) {
    final restored =
        session.uncertainUploadRecords.map((record) {
          final path = record.localPath ?? '';
          return CreatePostLocalAttachment(
            clientId: record.clientId,
            path: path,
            displayName: record.displayName,
            sizeBytes: record.sizeBytes,
            mimeType: record.mimeType,
            state: CreatePostAttachmentState.uncertain,
            userMessage: uncertainUploadBlockedMessage,
          );
        }).toList();
    return base.copyWith(items: restored);
  }

  void clearAll() {
    _publish(const CreatePostAttachmentsState());
  }

  void syncFromPostDetail(PostDetail detail) {
    final ids = detail.attachments.map((a) => a.id).toList();
    final revisionId = detail.editableRevisionId;
    if (revisionId != null) {
      ref
          .read(createPostSessionPersistenceProvider.notifier)
          .syncServerAttachments(revisionId: revisionId, attachmentIds: ids);
    }
    _publish(_held.copyWith(serverAttachmentIds: ids, clearBanner: true));
  }

  String? validatePickedFile(PickedPostFile file) {
    if (file.sizeBytes > PostAttachmentLimits.maxSizeBytes) {
      return 'Cada archivo puede pesar hasta 5 MB.';
    }
    if (!PostAttachmentLimits.allowedMimeTypes.contains(file.mimeType)) {
      return 'Tipo de archivo no permitido.';
    }
    final ext = file.displayName.split('.').last.toLowerCase();
    if (!PostAttachmentLimits.allowedExtensions.contains(ext)) {
      return 'Extensión no permitida.';
    }
    if (!File(file.path).existsSync()) {
      return 'No se pudo acceder al archivo seleccionado.';
    }
    if (_held.remainingSlots(_session) <= 0) {
      return 'Máximo ${PostAttachmentLimits.maxPerRevision} archivos por publicación.';
    }
    return null;
  }

  Future<String?> pickAndAddImage() async {
    if (!_held.canAddMore(_session)) {
      return 'Ya alcanzaste el máximo de archivos permitidos.';
    }
    final picked = await ref.read(createPostFilePickerProvider).pickImage();
    if (picked == null) {
      return null;
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
    if (!_held.canAddMore(_session)) {
      return 'Ya alcanzaste el máximo de archivos permitidos.';
    }
    final picked = await ref.read(createPostFilePickerProvider).pickPdf();
    if (picked == null) {
      return null;
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
    final next = [
      ..._held.items,
      CreatePostLocalAttachment(
        clientId: CreatePostLocalAttachment.newClientId(),
        path: picked.path,
        displayName: picked.displayName,
        sizeBytes: picked.sizeBytes,
        mimeType: picked.mimeType,
      ),
    ];
    _publish(_held.copyWith(items: next, clearBanner: true));
  }

  void removeLocal(String clientId) {
    final item = _held.items.firstWhere((e) => e.clientId == clientId);
    if (!item.canRemoveLocally) {
      return;
    }
    _publish(
      _held.copyWith(
        items: _held.items.where((e) => e.clientId != clientId).toList(),
      ),
    );
  }

  /// Solo para fallos inequívocos ([CreatePostAttachmentState.failed]).
  /// Devuelve false si el ítem es incierto o tiene registro persistente.
  bool markRetryAllowed(String clientId) {
    if (_session.hasUncertainClientId(clientId)) {
      return false;
    }
    CreatePostLocalAttachment? item;
    for (final e in _held.items) {
      if (e.clientId == clientId) {
        item = e;
        break;
      }
    }
    if (item == null || item.state != CreatePostAttachmentState.failed) {
      return false;
    }
    final next =
        _held.items.map((e) {
          if (e.clientId == clientId) {
            return e.copyWith(
              state: CreatePostAttachmentState.selected,
              clearUserMessage: true,
            );
          }
          return e;
        }).toList();
    _publish(_held.copyWith(items: next));
    return true;
  }

  void applyItemUpdate(CreatePostLocalAttachment updated) {
    final next =
        _held.items
            .map((e) => e.clientId == updated.clientId ? updated : e)
            .toList();
    _publish(_held.copyWith(items: next));
  }

  /// Solo para pruebas: fija la lista local sin pasar por el picker.
  @visibleForTesting
  void setLocalItemsForTests(List<CreatePostLocalAttachment> items) {
    _publish(_held.copyWith(items: items));
  }

  /// Snapshot local del servidor (la persistencia se actualiza en [CreatePostController]).
  void applyServerAttachmentSnapshot({
    required List<int> serverAttachmentIds,
    required bool unresolvedUncertain,
  }) {
    _publish(
      _held.copyWith(
        serverAttachmentIds: serverAttachmentIds,
        bannerMessage:
            unresolvedUncertain ? _reconcileInconclusiveMessage : null,
        clearBanner: !unresolvedUncertain,
      ),
    );
  }
}

final createPostAttachmentsProvider = NotifierProvider.autoDispose<
  CreatePostAttachmentsController,
  CreatePostAttachmentsState
>(CreatePostAttachmentsController.new);
