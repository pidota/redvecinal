import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import 'edit_post_uncertain_submit_record.dart';

class EditPostUncertainSubmitPersistenceState {
  const EditPostUncertainSubmitPersistenceState({
    this.recordsByPostId = const {},
  });

  final Map<int, EditPostUncertainSubmitRecord> recordsByPostId;

  EditPostUncertainSubmitRecord? recordForPost(int postId) =>
      recordsByPostId[postId];
}

class EditPostUncertainSubmitPersistence
    extends Notifier<EditPostUncertainSubmitPersistenceState> {
  int? _boundUserId;
  int? _boundEpoch;
  int _nextOperationGeneration = 1;
  EditPostUncertainSubmitPersistenceState _data =
      const EditPostUncertainSubmitPersistenceState();

  bool persistenceCommitEnabled = true;

  @override
  EditPostUncertainSubmitPersistenceState build() {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next is! AuthAuthenticated) {
        _boundUserId = null;
        _boundEpoch = null;
        _data = const EditPostUncertainSubmitPersistenceState();
        _commit(_data);
        return;
      }
      final userId = next.user.id;
      final epoch = ref.read(authControllerProvider.notifier).sessionEpoch;
      if (_boundUserId != userId || _boundEpoch != epoch) {
        _boundUserId = userId;
        _boundEpoch = epoch;
        _nextOperationGeneration = 1;
        _data = const EditPostUncertainSubmitPersistenceState();
        _commit(_data);
      }
    });

    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated) {
      _boundUserId = null;
      _boundEpoch = null;
      _data = const EditPostUncertainSubmitPersistenceState();
      return _data;
    }

    final userId = auth.user.id;
    final epoch = ref.read(authControllerProvider.notifier).sessionEpoch;
    if (_boundUserId != userId || _boundEpoch != epoch) {
      _boundUserId = userId;
      _boundEpoch = epoch;
      _nextOperationGeneration = 1;
      _data = const EditPostUncertainSubmitPersistenceState();
    }
    return _data;
  }

  void _commit(EditPostUncertainSubmitPersistenceState next) {
    _data = next;
    state = next;
  }

  bool sessionBindingActiveFor(int userId, int sessionEpoch) {
    return _boundUserId == userId && _boundEpoch == sessionEpoch;
  }

  int? beginSubmitAttempt({
    required int userId,
    required int sessionEpoch,
    required int postId,
    required int revisionId,
  }) {
    if (!persistenceCommitEnabled ||
        !sessionBindingActiveFor(userId, sessionEpoch)) {
      return null;
    }
    final generation = _nextOperationGeneration++;
    final record = EditPostUncertainSubmitRecord(
      userId: userId,
      sessionEpoch: sessionEpoch,
      postId: postId,
      revisionId: revisionId,
      operationGeneration: generation,
      phase: EditPostUncertainSubmitPhase.inFlight,
    );
    final nextMap = Map<int, EditPostUncertainSubmitRecord>.from(
      _data.recordsByPostId,
    )..[postId] = record;
    _commit(EditPostUncertainSubmitPersistenceState(recordsByPostId: nextMap));
    return generation;
  }

  EditPostUncertainSubmitRecord? peekRecordForPost(int postId) =>
      _data.recordsByPostId[postId];

  EditPostUncertainSubmitRecord? recordFor(int postId) {
    if (!_sameBoundSession()) {
      return null;
    }
    return _data.recordsByPostId[postId];
  }

  void removeRecordIfMatching(int postId, int operationGeneration) {
    final existing = _data.recordsByPostId[postId];
    if (existing == null ||
        existing.operationGeneration != operationGeneration) {
      return;
    }
    final nextMap = Map<int, EditPostUncertainSubmitRecord>.from(
      _data.recordsByPostId,
    )..remove(postId);
    _commit(EditPostUncertainSubmitPersistenceState(recordsByPostId: nextMap));
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
    final nextMap = Map<int, EditPostUncertainSubmitRecord>.from(
        _data.recordsByPostId,
      )
      ..[postId] = existing.copyWith(
        phase: EditPostUncertainSubmitPhase.outcomeUncertain,
      );
    _commit(EditPostUncertainSubmitPersistenceState(recordsByPostId: nextMap));
  }

  bool _sameBoundSession() {
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated) {
      return false;
    }
    return auth.user.id == _boundUserId &&
        ref.read(authControllerProvider.notifier).sessionEpoch == _boundEpoch;
  }
}

final editPostUncertainSubmitPersistenceProvider = NotifierProvider<
  EditPostUncertainSubmitPersistence,
  EditPostUncertainSubmitPersistenceState
>(EditPostUncertainSubmitPersistence.new);
