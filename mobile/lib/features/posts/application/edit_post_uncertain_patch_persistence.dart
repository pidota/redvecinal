import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import 'edit_post_uncertain_patch_record.dart';

/// Registros de PATCH incierto por postId; sobrevive al AutoDispose del editor.
///
/// Privacidad: el título y cuerpo del intento se guardan solo en memoria de la app,
/// alineado con [CreatePostSessionPersistence] (sin tokens; mismo alcance que el formulario).
class EditPostUncertainPatchPersistenceState {
  const EditPostUncertainPatchPersistenceState({
    this.recordsByPostId = const {},
  });

  final Map<int, EditPostUncertainPatchRecord> recordsByPostId;

  EditPostUncertainPatchRecord? recordForPost(int postId) =>
      recordsByPostId[postId];
}

class EditPostUncertainPatchPersistence
    extends Notifier<EditPostUncertainPatchPersistenceState> {
  int? _boundUserId;
  int? _boundEpoch;
  int _nextOperationGeneration = 1;
  EditPostUncertainPatchPersistenceState _data =
      const EditPostUncertainPatchPersistenceState();

  /// Solo pruebas: simular fallo al registrar intento.
  bool persistenceCommitEnabled = true;

  @override
  EditPostUncertainPatchPersistenceState build() {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next is! AuthAuthenticated) {
        _boundUserId = null;
        _boundEpoch = null;
        _data = const EditPostUncertainPatchPersistenceState();
        _commit(_data);
        return;
      }
      final userId = next.user.id;
      final epoch = ref.read(authControllerProvider.notifier).sessionEpoch;
      if (_boundUserId != userId || _boundEpoch != epoch) {
        _boundUserId = userId;
        _boundEpoch = epoch;
        _nextOperationGeneration = 1;
        _data = const EditPostUncertainPatchPersistenceState();
        _commit(_data);
      }
    });

    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated) {
      _boundUserId = null;
      _boundEpoch = null;
      _data = const EditPostUncertainPatchPersistenceState();
      return _data;
    }

    final userId = auth.user.id;
    final epoch = ref.read(authControllerProvider.notifier).sessionEpoch;
    if (_boundUserId != userId || _boundEpoch != epoch) {
      _boundUserId = userId;
      _boundEpoch = epoch;
      _nextOperationGeneration = 1;
      _data = const EditPostUncertainPatchPersistenceState();
      return _data;
    }

    return _data;
  }

  void _commit(EditPostUncertainPatchPersistenceState next) {
    _data = next;
    state = next;
  }

  bool _sameSession(int userId, int epoch) {
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated || auth.user.id != userId) {
      return false;
    }
    return ref.read(authControllerProvider.notifier).sessionEpoch == epoch &&
        epoch == _boundEpoch &&
        userId == _boundUserId;
  }

  /// Registra el intento antes del PATCH. Retorna `operationGeneration` o `null` si falla.
  int? beginPatchAttempt({
    required int userId,
    required int sessionEpoch,
    required int postId,
    required int revisionId,
    required int categoryId,
    required String title,
    required String body,
  }) {
    if (!persistenceCommitEnabled || !_sameSession(userId, sessionEpoch)) {
      return null;
    }
    final generation = _nextOperationGeneration++;
    final record = EditPostUncertainPatchRecord(
      userId: userId,
      sessionEpoch: sessionEpoch,
      postId: postId,
      revisionId: revisionId,
      categoryId: categoryId,
      title: title,
      body: body,
      operationGeneration: generation,
      phase: EditPostUncertainPatchPhase.inFlight,
    );
    final nextMap = Map<int, EditPostUncertainPatchRecord>.from(
      _data.recordsByPostId,
    )..[postId] = record;
    _commit(EditPostUncertainPatchPersistenceState(recordsByPostId: nextMap));
    return generation;
  }

  void confirmPatchSuccess(int postId, int operationGeneration) {
    _removeIfGeneration(postId, operationGeneration);
  }

  void confirmPatchFailure(int postId, int operationGeneration) {
    _removeIfGeneration(postId, operationGeneration);
  }

  void markOutcomeUncertain(int postId, int operationGeneration) {
    if (!_sameBoundSession()) {
      return;
    }
    final existing = _data.recordsByPostId[postId];
    if (existing == null ||
        existing.operationGeneration != operationGeneration) {
      return;
    }
    final nextMap = Map<int, EditPostUncertainPatchRecord>.from(
        _data.recordsByPostId,
      )
      ..[postId] = existing.copyWith(
        phase: EditPostUncertainPatchPhase.outcomeUncertain,
      );
    _commit(EditPostUncertainPatchPersistenceState(recordsByPostId: nextMap));
  }

  void clearAfterAdopt(int postId, int operationGeneration) {
    _removeIfGeneration(postId, operationGeneration);
  }

  EditPostUncertainPatchRecord? recordFor(int postId) {
    if (!_sameBoundSession()) {
      return null;
    }
    return _data.recordsByPostId[postId];
  }

  /// Lectura sin validar sesión actual (p. ej. al cerrar un PATCH en vuelo).
  EditPostUncertainPatchRecord? peekRecordForPost(int postId) =>
      _data.recordsByPostId[postId];

  bool sessionBindingActiveFor(int userId, int sessionEpoch) {
    return _boundUserId == userId && _boundEpoch == sessionEpoch;
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
    final nextMap = Map<int, EditPostUncertainPatchRecord>.from(
        _data.recordsByPostId,
      )
      ..[postId] = existing.copyWith(
        phase: EditPostUncertainPatchPhase.outcomeUncertain,
      );
    _commit(EditPostUncertainPatchPersistenceState(recordsByPostId: nextMap));
  }

  void removeRecordIfMatching(int postId, int operationGeneration) {
    final existing = _data.recordsByPostId[postId];
    if (existing == null ||
        existing.operationGeneration != operationGeneration) {
      return;
    }
    final nextMap = Map<int, EditPostUncertainPatchRecord>.from(
      _data.recordsByPostId,
    )..remove(postId);
    _commit(EditPostUncertainPatchPersistenceState(recordsByPostId: nextMap));
  }

  void _removeIfGeneration(int postId, int operationGeneration) {
    if (!_sameBoundSession()) {
      return;
    }
    final existing = _data.recordsByPostId[postId];
    if (existing == null ||
        existing.operationGeneration != operationGeneration) {
      return;
    }
    final nextMap = Map<int, EditPostUncertainPatchRecord>.from(
      _data.recordsByPostId,
    )..remove(postId);
    _commit(EditPostUncertainPatchPersistenceState(recordsByPostId: nextMap));
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

final editPostUncertainPatchPersistenceProvider = NotifierProvider<
  EditPostUncertainPatchPersistence,
  EditPostUncertainPatchPersistenceState
>(EditPostUncertainPatchPersistence.new);
