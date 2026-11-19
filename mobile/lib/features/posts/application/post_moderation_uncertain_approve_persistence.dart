import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import 'post_moderation_uncertain_approve_record.dart'
    show
        PostModerationDecisionKind,
        PostModerationUncertainApprovePhase,
        PostModerationUncertainApproveRecord;

class PostModerationUncertainApprovePersistenceState {
  const PostModerationUncertainApprovePersistenceState({
    this.recordsByPostId = const {},
  });

  final Map<int, PostModerationUncertainApproveRecord> recordsByPostId;

  PostModerationUncertainApproveRecord? recordForPost(int postId) =>
      recordsByPostId[postId];
}

class PostModerationUncertainApprovePersistence
    extends Notifier<PostModerationUncertainApprovePersistenceState> {
  int? _boundUserId;
  int? _boundEpoch;
  int _nextOperationGeneration = 1;
  PostModerationUncertainApprovePersistenceState _data =
      const PostModerationUncertainApprovePersistenceState();

  bool persistenceCommitEnabled = true;

  @override
  PostModerationUncertainApprovePersistenceState build() {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next is! AuthAuthenticated) {
        _boundUserId = null;
        _boundEpoch = null;
        _data = const PostModerationUncertainApprovePersistenceState();
        _commit(_data);
        return;
      }
      final userId = next.user.id;
      final epoch = ref.read(authControllerProvider.notifier).sessionEpoch;
      if (_boundUserId != userId || _boundEpoch != epoch) {
        _boundUserId = userId;
        _boundEpoch = epoch;
        _nextOperationGeneration = 1;
        _data = const PostModerationUncertainApprovePersistenceState();
        _commit(_data);
      }
    });

    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated) {
      _boundUserId = null;
      _boundEpoch = null;
      _data = const PostModerationUncertainApprovePersistenceState();
      return _data;
    }

    final userId = auth.user.id;
    final epoch = ref.read(authControllerProvider.notifier).sessionEpoch;
    if (_boundUserId != userId || _boundEpoch != epoch) {
      _boundUserId = userId;
      _boundEpoch = epoch;
      _nextOperationGeneration = 1;
      _data = const PostModerationUncertainApprovePersistenceState();
    }
    return _data;
  }

  void _commit(PostModerationUncertainApprovePersistenceState next) {
    _data = next;
    state = next;
  }

  bool sessionBindingActiveFor(int userId, int sessionEpoch) {
    return _boundUserId == userId && _boundEpoch == sessionEpoch;
  }

  int? beginApproveAttempt({
    required int userId,
    required int sessionEpoch,
    required int postId,
    required int pendingRevisionId,
  }) {
    return beginDecisionAttempt(
      userId: userId,
      sessionEpoch: sessionEpoch,
      postId: postId,
      pendingRevisionId: pendingRevisionId,
      decisionKind: PostModerationDecisionKind.approve,
    );
  }

  int? beginDecisionAttempt({
    required int userId,
    required int sessionEpoch,
    required int postId,
    required int pendingRevisionId,
    required PostModerationDecisionKind decisionKind,
  }) {
    if (!persistenceCommitEnabled ||
        !sessionBindingActiveFor(userId, sessionEpoch)) {
      return null;
    }
    if (_data.recordsByPostId.containsKey(postId)) {
      return null;
    }
    final generation = _nextOperationGeneration++;
    final record = PostModerationUncertainApproveRecord(
      userId: userId,
      sessionEpoch: sessionEpoch,
      postId: postId,
      pendingRevisionId: pendingRevisionId,
      operationGeneration: generation,
      phase: PostModerationUncertainApprovePhase.inFlight,
      decisionKind: decisionKind,
    );
    final nextMap = Map<int, PostModerationUncertainApproveRecord>.from(
      _data.recordsByPostId,
    )..[postId] = record;
    _commit(
      PostModerationUncertainApprovePersistenceState(recordsByPostId: nextMap),
    );
    return generation;
  }

  PostModerationUncertainApproveRecord? peekRecordForPost(int postId) =>
      _data.recordsByPostId[postId];

  void removeRecordIfMatching(int postId, int operationGeneration) {
    final existing = _data.recordsByPostId[postId];
    if (existing == null ||
        existing.operationGeneration != operationGeneration) {
      return;
    }
    final nextMap = Map<int, PostModerationUncertainApproveRecord>.from(
      _data.recordsByPostId,
    )..remove(postId);
    _commit(
      PostModerationUncertainApprovePersistenceState(recordsByPostId: nextMap),
    );
  }

  void promoteToOutcomeUncertainIfMatching(
    int postId,
    int operationGeneration,
  ) {
    final existing = _data.recordsByPostId[postId];
    if (existing == null ||
        existing.operationGeneration != operationGeneration) {
      return;
    }
    final nextMap = Map<int, PostModerationUncertainApproveRecord>.from(
        _data.recordsByPostId,
      )
      ..[postId] = existing.copyWith(
        phase: PostModerationUncertainApprovePhase.outcomeUncertain,
      );
    _commit(
      PostModerationUncertainApprovePersistenceState(recordsByPostId: nextMap),
    );
  }

  bool _sameBoundSession() {
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated) {
      return false;
    }
    final epoch = ref.read(authControllerProvider.notifier).sessionEpoch;
    return _boundUserId == auth.user.id && _boundEpoch == epoch;
  }

  PostModerationUncertainApproveRecord? recordFor(int postId) {
    if (!_sameBoundSession()) {
      return null;
    }
    return _data.recordsByPostId[postId];
  }
}

final postModerationUncertainApprovePersistenceProvider = NotifierProvider<
  PostModerationUncertainApprovePersistence,
  PostModerationUncertainApprovePersistenceState
>(PostModerationUncertainApprovePersistence.new);
