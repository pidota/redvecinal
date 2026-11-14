import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import '../../neighborhoods/application/neighborhood_session.dart';

/// Flags de create enlazados a [AuthController.sessionEpoch]; sobrevive al autoDispose del formulario.
class CreatePostSessionPersistenceState {
  const CreatePostSessionPersistenceState({
    this.uncertainCreate = false,
    this.confirmedDraftId,
  });

  final bool uncertainCreate;
  final int? confirmedDraftId;

  bool get blocksFullSend => uncertainCreate && confirmedDraftId == null;
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
