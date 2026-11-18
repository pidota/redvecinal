import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import 'edit_post_exclusive_operation.dart';
import 'edit_post_uncertain_upload_record.dart';

class _ExclusiveHolder {
  _ExclusiveHolder({
    required this.token,
    required this.userId,
    required this.sessionEpoch,
    required this.kind,
  });

  final int token;
  final int userId;
  final int sessionEpoch;
  final EditPostExclusiveOperationKind kind;
}

class EditPostAttachmentPersistenceRecord {
  const EditPostAttachmentPersistenceRecord({
    required this.userId,
    required this.sessionEpoch,
    required this.postId,
    required this.revisionId,
    this.serverAttachmentIds = const [],
    this.uncertainUploads = const [],
  });

  final int userId;
  final int sessionEpoch;
  final int postId;
  final int revisionId;
  final List<int> serverAttachmentIds;
  final List<EditPostUncertainUploadRecord> uncertainUploads;

  bool get hasUnresolvedUncertain => uncertainUploads.isNotEmpty;

  EditPostAttachmentPersistenceRecord copyWith({
    int? revisionId,
    List<int>? serverAttachmentIds,
    List<EditPostUncertainUploadRecord>? uncertainUploads,
  }) {
    return EditPostAttachmentPersistenceRecord(
      userId: userId,
      sessionEpoch: sessionEpoch,
      postId: postId,
      revisionId: revisionId ?? this.revisionId,
      serverAttachmentIds: serverAttachmentIds ?? this.serverAttachmentIds,
      uncertainUploads: uncertainUploads ?? this.uncertainUploads,
    );
  }
}

class EditPostAttachmentsPersistenceState {
  const EditPostAttachmentsPersistenceState({this.recordsByPostId = const {}});

  final Map<int, EditPostAttachmentPersistenceRecord> recordsByPostId;

  EditPostAttachmentPersistenceRecord? recordForPost(int postId) =>
      recordsByPostId[postId];
}

class EditPostAttachmentsPersistence
    extends Notifier<EditPostAttachmentsPersistenceState> {
  int? _boundUserId;
  int? _boundEpoch;
  final Map<int, _ExclusiveHolder> _exclusiveByPost = {};
  int _nextExclusiveToken = 1;
  EditPostAttachmentsPersistenceState _data =
      const EditPostAttachmentsPersistenceState();

  void _clearTransientSessionState() {
    _exclusiveByPost.clear();
  }

  EditPostExclusiveOperationKind? exclusiveKindForPost(int postId) =>
      _exclusiveByPost[postId]?.kind;

  bool blocksPatchForPost(int postId) {
    final record = _data.recordsByPostId[postId];
    final exclusive = _exclusiveByPost[postId];
    if (exclusive?.kind == EditPostExclusiveOperationKind.upload ||
        exclusive?.kind == EditPostExclusiveOperationKind.submit) {
      return true;
    }
    return record?.hasUnresolvedUncertain ?? false;
  }

  bool blocksUploadForPost(int postId) {
    final exclusive = _exclusiveByPost[postId];
    return exclusive?.kind == EditPostExclusiveOperationKind.patch ||
        exclusive?.kind == EditPostExclusiveOperationKind.submit;
  }

  bool blocksSubmitForPost(int postId) {
    final exclusive = _exclusiveByPost[postId];
    if (exclusive != null) {
      return true;
    }
    final record = _data.recordsByPostId[postId];
    return record?.hasUnresolvedUncertain ?? false;
  }

  /// Reserva síncrona; `null` si otra operación (misma sesión) ya tiene el post.
  EditPostOperationLease? tryAcquireExclusive({
    required int userId,
    required int sessionEpoch,
    required int postId,
    required EditPostExclusiveOperationKind kind,
  }) {
    if (!sessionBindingActiveFor(userId, sessionEpoch)) {
      return null;
    }
    final existing = _exclusiveByPost[postId];
    if (existing != null) {
      if (existing.userId != userId || existing.sessionEpoch != sessionEpoch) {
        return null;
      }
      return null;
    }
    final token = _nextExclusiveToken++;
    _exclusiveByPost[postId] = _ExclusiveHolder(
      token: token,
      userId: userId,
      sessionEpoch: sessionEpoch,
      kind: kind,
    );
    return EditPostOperationLease(
      token: token,
      postId: postId,
      userId: userId,
      sessionEpoch: sessionEpoch,
      kind: kind,
    );
  }

  bool releaseExclusive(EditPostOperationLease lease) {
    if (!sessionBindingActiveFor(lease.userId, lease.sessionEpoch)) {
      return false;
    }
    final existing = _exclusiveByPost[lease.postId];
    if (existing == null) {
      return false;
    }
    if (existing.token != lease.token) {
      return false;
    }
    if (existing.userId != lease.userId ||
        existing.sessionEpoch != lease.sessionEpoch) {
      return false;
    }
    _exclusiveByPost.remove(lease.postId);
    return true;
  }

  @override
  EditPostAttachmentsPersistenceState build() {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next is! AuthAuthenticated) {
        _boundUserId = null;
        _boundEpoch = null;
        _data = const EditPostAttachmentsPersistenceState();
        _clearTransientSessionState();
        state = _data;
        return;
      }
      final userId = next.user.id;
      final epoch = ref.read(authControllerProvider.notifier).sessionEpoch;
      if (_boundUserId != userId || _boundEpoch != epoch) {
        _boundUserId = userId;
        _boundEpoch = epoch;
        _data = const EditPostAttachmentsPersistenceState();
        _clearTransientSessionState();
        state = _data;
      }
    });

    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated) {
      _boundUserId = null;
      _boundEpoch = null;
      _data = const EditPostAttachmentsPersistenceState();
      return _data;
    }

    final userId = auth.user.id;
    final epoch = ref.read(authControllerProvider.notifier).sessionEpoch;
    if (_boundUserId != userId || _boundEpoch != epoch) {
      _boundUserId = userId;
      _boundEpoch = epoch;
      _data = const EditPostAttachmentsPersistenceState();
      _clearTransientSessionState();
    }
    return _data;
  }

  void _commit(EditPostAttachmentsPersistenceState next) {
    _data = next;
    state = next;
  }

  bool sessionBindingActiveFor(int userId, int sessionEpoch) {
    return _boundUserId == userId && _boundEpoch == sessionEpoch;
  }

  EditPostAttachmentPersistenceRecord? peekRecordForPost(int postId) =>
      _data.recordsByPostId[postId];

  void syncServerAttachments({
    required int userId,
    required int sessionEpoch,
    required int postId,
    required int revisionId,
    required List<int> attachmentIds,
  }) {
    if (!sessionBindingActiveFor(userId, sessionEpoch)) {
      return;
    }
    final existing = _data.recordsByPostId[postId];
    final nextRecord =
        (existing == null ||
                existing.userId != userId ||
                existing.sessionEpoch != sessionEpoch)
            ? EditPostAttachmentPersistenceRecord(
              userId: userId,
              sessionEpoch: sessionEpoch,
              postId: postId,
              revisionId: revisionId,
              serverAttachmentIds: attachmentIds,
            )
            : existing.copyWith(
              revisionId: revisionId,
              serverAttachmentIds: attachmentIds,
            );
    final nextMap = Map<int, EditPostAttachmentPersistenceRecord>.from(
      _data.recordsByPostId,
    )..[postId] = nextRecord;
    _commit(EditPostAttachmentsPersistenceState(recordsByPostId: nextMap));
  }

  void registerUncertainUpload(EditPostUncertainUploadRecord record) {
    if (!sessionBindingActiveFor(record.userId, record.sessionEpoch)) {
      return;
    }
    final existing = _data.recordsByPostId[record.postId];
    final uncertain =
        existing == null
            ? [record]
            : [
              ...existing.uncertainUploads.where(
                (e) => e.clientId != record.clientId,
              ),
              record,
            ];
    final base =
        existing ??
        EditPostAttachmentPersistenceRecord(
          userId: record.userId,
          sessionEpoch: record.sessionEpoch,
          postId: record.postId,
          revisionId: record.revisionId,
        );
    final nextMap = Map<int, EditPostAttachmentPersistenceRecord>.from(
      _data.recordsByPostId,
    )..[record.postId] = base.copyWith(uncertainUploads: uncertain);
    _commit(EditPostAttachmentsPersistenceState(recordsByPostId: nextMap));
  }

  void resolveUncertainUpload({required int postId, required String clientId}) {
    final existing = _data.recordsByPostId[postId];
    if (existing == null) {
      return;
    }
    final nextUncertain =
        existing.uncertainUploads.where((e) => e.clientId != clientId).toList();
    final nextMap = Map<int, EditPostAttachmentPersistenceRecord>.from(
      _data.recordsByPostId,
    )..[postId] = existing.copyWith(uncertainUploads: nextUncertain);
    _commit(EditPostAttachmentsPersistenceState(recordsByPostId: nextMap));
  }

  void recordUploadedAttachment({
    required int postId,
    required int attachmentId,
  }) {
    final existing = _data.recordsByPostId[postId];
    if (existing == null) {
      return;
    }
    if (existing.serverAttachmentIds.contains(attachmentId)) {
      return;
    }
    final nextMap = Map<int, EditPostAttachmentPersistenceRecord>.from(
        _data.recordsByPostId,
      )
      ..[postId] = existing.copyWith(
        serverAttachmentIds: [...existing.serverAttachmentIds, attachmentId],
      );
    _commit(EditPostAttachmentsPersistenceState(recordsByPostId: nextMap));
  }

  void promoteUncertainIfMatching({
    required int postId,
    required String clientId,
    required int attachmentId,
  }) {
    final existing = _data.recordsByPostId[postId];
    if (existing == null) {
      return;
    }
    final nextUncertain =
        existing.uncertainUploads.where((e) => e.clientId != clientId).toList();
    final ids =
        existing.serverAttachmentIds.contains(attachmentId)
            ? existing.serverAttachmentIds
            : [...existing.serverAttachmentIds, attachmentId];
    final nextMap = Map<int, EditPostAttachmentPersistenceRecord>.from(
        _data.recordsByPostId,
      )
      ..[postId] = existing.copyWith(
        uncertainUploads: nextUncertain,
        serverAttachmentIds: ids,
      );
    _commit(EditPostAttachmentsPersistenceState(recordsByPostId: nextMap));
  }

  void clearPostIfMatching({
    required int postId,
    required int userId,
    required int sessionEpoch,
  }) {
    if (!sessionBindingActiveFor(userId, sessionEpoch)) {
      return;
    }
    final existing = _data.recordsByPostId[postId];
    if (existing == null) {
      return;
    }
    final nextMap = Map<int, EditPostAttachmentPersistenceRecord>.from(
      _data.recordsByPostId,
    )..remove(postId);
    _commit(EditPostAttachmentsPersistenceState(recordsByPostId: nextMap));
  }
}

final editPostAttachmentsPersistenceProvider = NotifierProvider<
  EditPostAttachmentsPersistence,
  EditPostAttachmentsPersistenceState
>(EditPostAttachmentsPersistence.new);
