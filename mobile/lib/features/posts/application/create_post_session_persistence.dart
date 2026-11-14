import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import 'create_post_uncertain_upload_record.dart';

/// Flags de create enlazados a [AuthController.sessionEpoch]; sobrevive al autoDispose del formulario.
class CreatePostSessionPersistenceState {
  const CreatePostSessionPersistenceState({
    this.uncertainCreate = false,
    this.confirmedDraftId,
    this.confirmedRevisionId,
    this.serverAttachmentIds = const [],
    this.uncertainUploadRecords = const [],
    this.linkedDraftPending = false,
  });

  final bool uncertainCreate;
  final int? confirmedDraftId;
  final int? confirmedRevisionId;
  final List<int> serverAttachmentIds;
  final List<CreatePostUncertainUploadRecord> uncertainUploadRecords;

  /// Borrador enlazado ya enviado a moderación (no subir ni submit).
  final bool linkedDraftPending;

  bool get hasUnresolvedUncertainUpload => uncertainUploadRecords.isNotEmpty;

  bool hasUncertainClientId(String clientId) =>
      uncertainUploadRecords.any((e) => e.clientId == clientId);

  bool get blocksFullSend =>
      (uncertainCreate && confirmedDraftId == null) ||
      hasUnresolvedUncertainUpload ||
      linkedDraftPending;
}

class CreatePostSessionPersistence
    extends Notifier<CreatePostSessionPersistenceState> {
  int? _boundEpoch;
  CreatePostSessionPersistenceState _flags =
      const CreatePostSessionPersistenceState();

  @override
  CreatePostSessionPersistenceState build() {
    ref.watch(authControllerProvider);
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated) {
      _boundEpoch = null;
      _flags = const CreatePostSessionPersistenceState();
      return _flags;
    }

    final epoch = ref.read(authControllerProvider.notifier).sessionEpoch;
    if (_boundEpoch != epoch) {
      _boundEpoch = epoch;
      _flags = const CreatePostSessionPersistenceState();
      return _flags;
    }

    return _flags;
  }

  void _commit(CreatePostSessionPersistenceState next) {
    _flags = next;
    state = next;
  }

  void markUncertainCreate() {
    if (!_sameEpoch()) {
      return;
    }
    _commit(
      CreatePostSessionPersistenceState(
        uncertainCreate: true,
        confirmedDraftId: _flags.confirmedDraftId,
        confirmedRevisionId: _flags.confirmedRevisionId,
        serverAttachmentIds: _flags.serverAttachmentIds,
        uncertainUploadRecords: _flags.uncertainUploadRecords,
        linkedDraftPending: _flags.linkedDraftPending,
      ),
    );
  }

  void setConfirmedDraftId(int id, {required bool clearUncertain}) {
    if (!_sameEpoch()) {
      return;
    }
    _commit(
      CreatePostSessionPersistenceState(
        uncertainCreate: clearUncertain ? false : _flags.uncertainCreate,
        confirmedDraftId: id,
        confirmedRevisionId: _flags.confirmedRevisionId,
        serverAttachmentIds: _flags.serverAttachmentIds,
        uncertainUploadRecords: _flags.uncertainUploadRecords,
        linkedDraftPending: _flags.linkedDraftPending,
      ),
    );
  }

  void setConfirmedRevisionId(int revisionId) {
    if (!_sameEpoch()) {
      return;
    }
    _commit(
      CreatePostSessionPersistenceState(
        uncertainCreate: _flags.uncertainCreate,
        confirmedDraftId: _flags.confirmedDraftId,
        confirmedRevisionId: revisionId,
        serverAttachmentIds: _flags.serverAttachmentIds,
        uncertainUploadRecords: _flags.uncertainUploadRecords,
        linkedDraftPending: _flags.linkedDraftPending,
      ),
    );
  }

  void registerUncertainUpload(CreatePostUncertainUploadRecord record) {
    if (!_sameEpoch()) {
      return;
    }
    if (_flags.uncertainUploadRecords.any(
      (e) => e.clientId == record.clientId,
    )) {
      return;
    }
    _commit(
      CreatePostSessionPersistenceState(
        uncertainCreate: _flags.uncertainCreate,
        confirmedDraftId: _flags.confirmedDraftId,
        confirmedRevisionId: _flags.confirmedRevisionId,
        serverAttachmentIds: _flags.serverAttachmentIds,
        uncertainUploadRecords: [..._flags.uncertainUploadRecords, record],
        linkedDraftPending: _flags.linkedDraftPending,
      ),
    );
  }

  void resolveUncertainUpload(String clientId) {
    if (!_sameEpoch()) {
      return;
    }
    final nextRecords =
        _flags.uncertainUploadRecords
            .where((e) => e.clientId != clientId)
            .toList();
    _commit(
      CreatePostSessionPersistenceState(
        uncertainCreate: _flags.uncertainCreate,
        confirmedDraftId: _flags.confirmedDraftId,
        confirmedRevisionId: _flags.confirmedRevisionId,
        serverAttachmentIds: _flags.serverAttachmentIds,
        uncertainUploadRecords: nextRecords,
        linkedDraftPending: _flags.linkedDraftPending,
      ),
    );
  }

  void recordUploadedAttachment(int attachmentId) {
    if (!_sameEpoch()) {
      return;
    }
    if (_flags.serverAttachmentIds.contains(attachmentId)) {
      return;
    }
    _commit(
      CreatePostSessionPersistenceState(
        uncertainCreate: _flags.uncertainCreate,
        confirmedDraftId: _flags.confirmedDraftId,
        confirmedRevisionId: _flags.confirmedRevisionId,
        serverAttachmentIds: [..._flags.serverAttachmentIds, attachmentId],
        uncertainUploadRecords: _flags.uncertainUploadRecords,
        linkedDraftPending: _flags.linkedDraftPending,
      ),
    );
  }

  void syncServerAttachments({
    required int revisionId,
    required List<int> attachmentIds,
  }) {
    if (!_sameEpoch()) {
      return;
    }
    _commit(
      CreatePostSessionPersistenceState(
        uncertainCreate: _flags.uncertainCreate,
        confirmedDraftId: _flags.confirmedDraftId,
        confirmedRevisionId: revisionId,
        serverAttachmentIds: attachmentIds,
        uncertainUploadRecords: _flags.uncertainUploadRecords,
        linkedDraftPending: _flags.linkedDraftPending,
      ),
    );
  }

  void setLinkedDraftPending(bool value) {
    if (!_sameEpoch()) {
      return;
    }
    _commit(
      CreatePostSessionPersistenceState(
        uncertainCreate: _flags.uncertainCreate,
        confirmedDraftId: _flags.confirmedDraftId,
        confirmedRevisionId: _flags.confirmedRevisionId,
        serverAttachmentIds: _flags.serverAttachmentIds,
        uncertainUploadRecords: _flags.uncertainUploadRecords,
        linkedDraftPending: value,
      ),
    );
  }

  void clearAll() {
    if (_sameEpoch()) {
      _commit(const CreatePostSessionPersistenceState());
    } else {
      _flags = const CreatePostSessionPersistenceState();
      _boundEpoch = neighborhoodSessionEpoch(ref);
      if (_boundEpoch != null) {
        state = _flags;
      }
    }
  }

  bool _sameEpoch() {
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated) {
      return false;
    }
    final epoch = ref.read(authControllerProvider.notifier).sessionEpoch;
    return epoch == _boundEpoch;
  }
}

final createPostSessionPersistenceProvider = NotifierProvider<
  CreatePostSessionPersistence,
  CreatePostSessionPersistenceState
>(CreatePostSessionPersistence.new);

final createPostSessionEpochProvider = Provider.autoDispose<int?>((ref) {
  ref.watch(authControllerProvider);
  return neighborhoodSessionEpoch(ref);
});
