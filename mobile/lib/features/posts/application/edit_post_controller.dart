import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import '../data/models/post_detail.dart';
import '../data/post_repository.dart';
import 'edit_post_attachments_controller.dart';
import 'edit_post_attachments_persistence.dart';
import 'edit_post_exclusive_operation.dart';
import 'edit_post_patch_support.dart';
import 'edit_post_reconcile_observation.dart';
import 'edit_post_uncertain_patch_persistence.dart';
import 'edit_post_uncertain_patch_record.dart';
import 'edit_post_submit_support.dart';
import 'edit_post_uncertain_submit_persistence.dart';
import 'edit_post_uncertain_submit_record.dart';
import 'my_posts_controller.dart';

/// Vista hidratada tras GET; independiente del listado.
class EditPostSnapshot {
  const EditPostSnapshot({
    required this.detail,
    required this.editable,
    required this.editableRevisionId,
    required this.readOnlyAttachments,
    this.blockMessage,
  });

  final PostDetail detail;
  final bool editable;
  final int? editableRevisionId;
  final List<PostAttachment> readOnlyAttachments;
  final String? blockMessage;

  static EditPostSnapshot fromDetail(PostDetail detail) {
    final working = detail.workingContent;
    final revisionId = detail.editableRevisionId;
    final hasGroup = detail.neighborhoodGroup != null;
    final hasCategory = detail.category != null;
    final statusOk = detail.status == 'draft' || detail.status == 'rejected';
    final editable =
        !detail.isMunicipal &&
        statusOk &&
        working != null &&
        revisionId != null &&
        hasGroup &&
        hasCategory;

    String? block;
    if (detail.isMunicipal) {
      block = 'Los comunicados municipales no se editan desde la app.';
    } else if (detail.status == 'pending') {
      block =
          'Esta publicación está en moderación y no puede editarse desde la app.';
    } else if (detail.status == 'published') {
      block = 'Las publicaciones publicadas no se editan en esta versión.';
    } else if (detail.status == 'hidden' || detail.status == 'archived') {
      block = 'Esta publicación no admite edición en su estado actual.';
    } else if (working == null || revisionId == null) {
      block =
          'No pudimos identificar el contenido editable. Actualiza e intenta de nuevo.';
    } else if (!hasGroup || !hasCategory) {
      block =
          'Faltan datos del grupo o la categoría para editar con seguridad.';
    } else if (!statusOk) {
      block = 'Esta publicación no admite edición.';
    }

    final attachments =
        revisionId == null
            ? const <PostAttachment>[]
            : detail.attachments
                .where((a) => a.revisionId == revisionId)
                .toList();

    return EditPostSnapshot(
      detail: detail,
      editable: editable,
      editableRevisionId: revisionId,
      readOnlyAttachments: attachments,
      blockMessage: editable ? null : block,
    );
  }
}

class EditPostSession {
  const EditPostSession({
    required this.snapshot,
    this.patchUncertain = false,
    this.uncertainPhase,
    this.saveInFlight = false,
    this.saveFailure,
    this.saveSuccessTick = 0,
    this.submitInFlight = false,
    this.submitUncertain = false,
    this.submitUncertainPhase,
    this.submitFailure,
  });

  final EditPostSnapshot snapshot;
  final bool patchUncertain;
  final EditPostUncertainPatchPhase? uncertainPhase;
  final bool saveInFlight;
  final ApiFailure? saveFailure;
  final int saveSuccessTick;
  final bool submitInFlight;
  final bool submitUncertain;
  final EditPostUncertainSubmitPhase? submitUncertainPhase;
  final ApiFailure? submitFailure;

  EditPostSession copyWith({
    EditPostSnapshot? snapshot,
    bool? patchUncertain,
    EditPostUncertainPatchPhase? uncertainPhase,
    bool clearUncertainPhase = false,
    bool? saveInFlight,
    ApiFailure? saveFailure,
    int? saveSuccessTick,
    bool clearSaveFailure = false,
    bool? submitInFlight,
    bool? submitUncertain,
    EditPostUncertainSubmitPhase? submitUncertainPhase,
    bool clearSubmitUncertainPhase = false,
    ApiFailure? submitFailure,
    bool clearSubmitFailure = false,
  }) {
    return EditPostSession(
      snapshot: snapshot ?? this.snapshot,
      patchUncertain: patchUncertain ?? this.patchUncertain,
      uncertainPhase:
          clearUncertainPhase ? null : (uncertainPhase ?? this.uncertainPhase),
      saveInFlight: saveInFlight ?? this.saveInFlight,
      saveFailure: clearSaveFailure ? null : (saveFailure ?? this.saveFailure),
      saveSuccessTick: saveSuccessTick ?? this.saveSuccessTick,
      submitInFlight: submitInFlight ?? this.submitInFlight,
      submitUncertain: submitUncertain ?? this.submitUncertain,
      submitUncertainPhase:
          clearSubmitUncertainPhase
              ? null
              : (submitUncertainPhase ?? this.submitUncertainPhase),
      submitFailure:
          clearSubmitFailure ? null : (submitFailure ?? this.submitFailure),
    );
  }
}

sealed class EditPostSaveResult {
  const EditPostSaveResult();
}

class EditPostSaveSuccess extends EditPostSaveResult {
  const EditPostSaveSuccess(this.detail);

  final PostDetail detail;
}

class EditPostSaveFailure extends EditPostSaveResult {
  const EditPostSaveFailure(this.failure);

  final ApiFailure failure;
}

class EditPostSaveUncertain extends EditPostSaveResult {
  const EditPostSaveUncertain();
}

class EditPostSaveDiscarded extends EditPostSaveResult {
  const EditPostSaveDiscarded();
}

class EditPostSaveInFlight extends EditPostSaveResult {
  const EditPostSaveInFlight();
}

class EditPostSaveBlocked extends EditPostSaveResult {
  const EditPostSaveBlocked(this.message);

  final String message;
}

sealed class EditPostSubmitResult {
  const EditPostSubmitResult();
}

class EditPostSubmitSuccess extends EditPostSubmitResult {
  const EditPostSubmitSuccess(this.detail);

  final PostDetail detail;
}

class EditPostSubmitFailure extends EditPostSubmitResult {
  const EditPostSubmitFailure(this.failure);

  final ApiFailure failure;
}

class EditPostSubmitUncertain extends EditPostSubmitResult {
  const EditPostSubmitUncertain();
}

class EditPostSubmitDiscarded extends EditPostSubmitResult {
  const EditPostSubmitDiscarded();
}

class EditPostSubmitInFlight extends EditPostSubmitResult {
  const EditPostSubmitInFlight();
}

class EditPostSubmitBlocked extends EditPostSubmitResult {
  const EditPostSubmitBlocked(this.message);

  final String message;
}

sealed class EditPostSubmitReconcileResult {
  const EditPostSubmitReconcileResult();
}

class EditPostSubmitReconcileObservedPending
    extends EditPostSubmitReconcileResult {
  const EditPostSubmitReconcileObservedPending(this.detail, this.message);

  final PostDetail detail;
  final String message;
}

class EditPostSubmitReconcileStillUncertain
    extends EditPostSubmitReconcileResult {
  const EditPostSubmitReconcileStillUncertain(this.message);

  final String message;
}

class EditPostSubmitReconcileDiscarded extends EditPostSubmitReconcileResult {
  const EditPostSubmitReconcileDiscarded();
}

class EditPostSubmitReconcileGetFailed extends EditPostSubmitReconcileResult {
  const EditPostSubmitReconcileGetFailed(this.failure);

  final ApiFailure failure;
}

sealed class EditPostReconcileResult {
  const EditPostReconcileResult();
}

/// El servidor ya no permite editar (p. ej. pasó a pending).
class EditPostReconcileRemoteChanged extends EditPostReconcileResult {
  const EditPostReconcileRemoteChanged(this.detail, this.message);

  final PostDetail detail;
  final String message;
}

/// Contenido remoto distinto al intento guardado; no se adopta en silencio.
class EditPostReconcileRemoteConflict extends EditPostReconcileResult {
  const EditPostReconcileRemoteConflict(this.message);

  final String message;
}

class EditPostReconcileStillUncertain extends EditPostReconcileResult {
  const EditPostReconcileStillUncertain(this.message);

  final String message;
}

class EditPostReconcileDiscarded extends EditPostReconcileResult {
  const EditPostReconcileDiscarded();
}

/// Coincidencia observable en GET sin confirmar la respuesta HTTP del PATCH.
class EditPostReconcileObservableMatch extends EditPostReconcileResult {
  const EditPostReconcileObservableMatch(this.message);

  final String message;
}

sealed class EditPostAdoptResult {
  const EditPostAdoptResult();
}

class EditPostAdoptSuccess extends EditPostAdoptResult {
  const EditPostAdoptSuccess(this.detail);

  final PostDetail detail;
}

class EditPostAdoptBlocked extends EditPostAdoptResult {
  const EditPostAdoptBlocked(this.message);

  final String message;
}

class EditPostAdoptDiscarded extends EditPostAdoptResult {
  const EditPostAdoptDiscarded();
}

class EditPostController
    extends AutoDisposeFamilyAsyncNotifier<EditPostSession, int> {
  int _loadGeneration = 0;
  int _editorContentGeneration = 0;
  int _saveGeneration = 0;
  int? _activeSaveGeneration;
  EditPostPatchPayload? _pendingUncertainPayload;
  int? _activePatchOperationGeneration;
  int _reconcileGeneration = 0;
  EditPostReconcileObservation? _lastReconcileObservation;
  int? _activeSubmitGeneration;
  EditPostSubmitPayload? _pendingUncertainSubmit;
  int _submitGeneration = 0;

  bool get isPatchInFlight => _activeSaveGeneration != null;

  EditPostPatchPayload? get pendingUncertainPayload => _pendingUncertainPayload;

  EditPostReconcileObservation? get lastReconcileObservation =>
      _lastReconcileObservation;

  @visibleForTesting
  void debugReplaceObservationRemote(PostDetail remote) {
    final observation = _lastReconcileObservation;
    if (observation == null) {
      return;
    }
    _lastReconcileObservation = EditPostReconcileObservation(
      remote: remote,
      operationGeneration: observation.operationGeneration,
      reconcileGeneration: observation.reconcileGeneration,
      contentMatchesPending: observation.contentMatchesPending,
    );
  }

  @visibleForTesting
  void debugInvalidateReconcileObservation() {
    _reconcileGeneration++;
  }

  @visibleForTesting
  void debugInvalidateActiveSaveEpoch() {
    _saveGeneration++;
  }

  @visibleForTesting
  int get editorLoadGeneration => _loadGeneration;

  @visibleForTesting
  int get editorContentGeneration => _editorContentGeneration;

  @visibleForTesting
  void debugAdvanceEditorContentGeneration() {
    _editorContentGeneration++;
  }

  void _syncAttachmentsAfterEditorSnapshot(
    EditPostSnapshot snap, {
    required int editorLoadGeneration,
  }) {
    ref
        .read(editPostAttachmentsControllerProvider(arg).notifier)
        .syncFromEditorSnapshot(
          editorLoadGeneration: editorLoadGeneration,
          editable: snap.editable,
          editableRevisionId: snap.editableRevisionId,
          serverAttachments: snap.readOnlyAttachments,
          blockMessage: snap.blockMessage,
        );
  }

  EditPostUncertainPatchPersistence get _patchPersistence =>
      ref.read(editPostUncertainPatchPersistenceProvider.notifier);

  EditPostUncertainSubmitPersistence get _submitPersistence =>
      ref.read(editPostUncertainSubmitPersistenceProvider.notifier);

  EditPostSubmitPayload? get pendingUncertainSubmit => _pendingUncertainSubmit;

  int? _authenticatedUserId() {
    final auth = ref.read(authControllerProvider);
    return auth is AuthAuthenticated ? auth.user.id : null;
  }

  bool get isSaveInFlight =>
      _activeSaveGeneration != null ||
      (state.valueOrNull?.saveInFlight ?? false);

  @override
  Future<EditPostSession> build(int postId) async {
    ref.watch(authControllerProvider);
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      throw StateError('Sin sesión');
    }
    final generation = ++_loadGeneration;
    final detail = await ref.read(postRepositoryProvider).getPost(postId);
    if (generation != _loadGeneration ||
        neighborhoodSessionEpoch(ref) != epoch) {
      throw StateError('Carga descartada');
    }
    final session = EditPostSession(
      snapshot: EditPostSnapshot.fromDetail(detail),
    );
    final record = _patchPersistence.recordFor(arg);
    if (record != null) {
      _pendingUncertainPayload = record.toPayload();
      return session.copyWith(
        patchUncertain: true,
        uncertainPhase: record.phase,
      );
    }
    final submitRecord = _submitPersistence.recordFor(arg);
    if (submitRecord != null) {
      _pendingUncertainSubmit = submitRecord.toPayload();
      return session.copyWith(
        submitUncertain: true,
        submitUncertainPhase: submitRecord.phase,
      );
    }
    return session;
  }

  void _resolveDiscardedPatchAttempt({
    required EditPostUncertainPatchPersistence persistence,
    required int postId,
    required int patchOpGeneration,
    required EditPostPatchPayload payload,
    required bool requestDispatched,
  }) {
    if (!requestDispatched) {
      persistence.removeRecordIfMatching(postId, patchOpGeneration);
      return;
    }
    persistence.promoteToOutcomeUncertainIfMatching(postId, patchOpGeneration);
    final record = persistence.peekRecordForPost(postId);
    if (record == null ||
        record.operationGeneration != patchOpGeneration ||
        record.phase != EditPostUncertainPatchPhase.outcomeUncertain) {
      return;
    }
    if (!persistence.sessionBindingActiveFor(
      record.userId,
      record.sessionEpoch,
    )) {
      return;
    }
    final value = state.valueOrNull;
    if (value == null) {
      return;
    }
    _pendingUncertainPayload = payload;
    state = AsyncValue.data(
      value.copyWith(
        saveInFlight: false,
        patchUncertain: true,
        uncertainPhase: EditPostUncertainPatchPhase.outcomeUncertain,
        clearSaveFailure: true,
      ),
    );
  }

  bool _patchAttemptStillActive({
    required EditPostUncertainPatchPersistence persistence,
    required int userId,
    required int sessionEpoch,
    required int saveGeneration,
    required int patchOpGeneration,
    required int postId,
  }) {
    if (saveGeneration != _saveGeneration) {
      return false;
    }
    if (!persistence.sessionBindingActiveFor(userId, sessionEpoch)) {
      return false;
    }
    final record = persistence.peekRecordForPost(postId);
    if (record == null) {
      return false;
    }
    if (record.operationGeneration != patchOpGeneration) {
      return false;
    }
    return record.sessionEpoch == sessionEpoch;
  }

  Future<void> reload() async {
    if (_activeSaveGeneration != null) {
      return;
    }

    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      state = AsyncValue.error(StateError('Sin sesión'), StackTrace.current);
      return;
    }

    final generation = ++_loadGeneration;
    final previous = state.valueOrNull;
    if (previous == null) {
      state = const AsyncValue.loading();
    }

    try {
      final detail = await ref.read(postRepositoryProvider).getPost(arg);
      if (generation != _loadGeneration ||
          neighborhoodSessionEpoch(ref) != epoch) {
        return;
      }
      final snap = EditPostSnapshot.fromDetail(detail);
      final record = _patchPersistence.recordFor(arg);
      final patchUncertain = previous?.patchUncertain ?? record != null;
      if (record != null) {
        _pendingUncertainPayload = record.toPayload();
      }
      state = AsyncValue.data(
        EditPostSession(
          snapshot: snap,
          patchUncertain: patchUncertain,
          uncertainPhase: record?.phase ?? previous?.uncertainPhase,
          saveFailure: previous?.saveFailure,
          saveSuccessTick: previous?.saveSuccessTick ?? 0,
        ),
      );
      final syncGen = ++_editorContentGeneration;
      _syncAttachmentsAfterEditorSnapshot(snap, editorLoadGeneration: syncGen);
    } catch (e, st) {
      if (generation != _loadGeneration) {
        return;
      }
      state = AsyncValue.error(e, st);
    }
  }

  Future<EditPostSaveResult> save({
    required int categoryId,
    required String title,
    required String body,
  }) async {
    final current = state.valueOrNull;
    if (current == null) {
      return const EditPostSaveBlocked(
        'Aún cargamos la publicación. Espera un momento.',
      );
    }
    if (_activeSaveGeneration != null || current.saveInFlight) {
      return const EditPostSaveInFlight();
    }
    if (current.patchUncertain) {
      return const EditPostSaveBlocked(
        'Hay un guardado con resultado incierto. Usa «Verificar en servidor» antes de guardar de nuevo.',
      );
    }
    final attachPersistence = ref.read(
      editPostAttachmentsPersistenceProvider.notifier,
    );
    if (attachPersistence.blocksPatchForPost(arg)) {
      return const EditPostSaveBlocked(
        'Hay adjuntos subiendo o con resultado incierto. Resuélvelo antes de guardar el texto.',
      );
    }
    if (!current.snapshot.editable) {
      return EditPostSaveBlocked(
        current.snapshot.blockMessage ?? 'No se puede guardar en este estado.',
      );
    }

    final trimmedTitle = title.trim();
    final trimmedBody = body.trim();
    if (trimmedTitle.isEmpty || trimmedBody.isEmpty) {
      return const EditPostSaveBlocked('Título y contenido son obligatorios.');
    }
    if (trimmedTitle.length > 200 || trimmedBody.length > 50000) {
      return const EditPostSaveBlocked(
        'El título o el contenido superan el límite permitido.',
      );
    }

    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return const EditPostSaveDiscarded();
    }

    final revisionId = current.snapshot.editableRevisionId;
    if (revisionId == null) {
      return const EditPostSaveBlocked(
        'No hay una revisión editable para guardar.',
      );
    }

    final userId = _authenticatedUserId();
    if (userId == null) {
      return const EditPostSaveDiscarded();
    }

    final contentEpochAtSave = _editorContentGeneration;

    final patchLease = attachPersistence.tryAcquireExclusive(
      userId: userId,
      sessionEpoch: epoch,
      postId: arg,
      kind: EditPostExclusiveOperationKind.patch,
    );
    if (patchLease == null) {
      return const EditPostSaveBlocked(
        'Hay otra operación en curso (guardado o subida). Espera a que termine.',
      );
    }

    final persistence = ref.read(
      editPostUncertainPatchPersistenceProvider.notifier,
    );
    final patchOpGeneration = persistence.beginPatchAttempt(
      userId: userId,
      sessionEpoch: epoch,
      postId: arg,
      revisionId: revisionId,
      categoryId: categoryId,
      title: trimmedTitle,
      body: trimmedBody,
    );
    if (patchOpGeneration == null) {
      attachPersistence.releaseExclusive(patchLease);
      return const EditPostSaveBlocked(
        'No pudimos registrar el intento de guardado de forma segura. '
        'Inténtalo de nuevo en un momento.',
      );
    }

    final saveGeneration = ++_saveGeneration;
    _activeSaveGeneration = saveGeneration;
    _activePatchOperationGeneration = patchOpGeneration;
    final patchPayload = EditPostPatchPayload(
      postId: arg,
      revisionId: revisionId,
      categoryId: categoryId,
      title: trimmedTitle,
      body: trimmedBody,
      sessionEpoch: epoch,
      saveGeneration: saveGeneration,
    );

    state = AsyncValue.data(
      current.copyWith(saveInFlight: true, clearSaveFailure: true),
    );

    var requestDispatched = false;
    EditPostSaveResult? result;
    try {
      requestDispatched = true;
      final updated = await ref
          .read(postRepositoryProvider)
          .updatePost(
            postId: patchPayload.postId,
            categoryId: patchPayload.categoryId,
            title: patchPayload.title,
            body: patchPayload.body,
          );

      if (!_patchAttemptStillActive(
        persistence: persistence,
        userId: userId,
        sessionEpoch: epoch,
        saveGeneration: saveGeneration,
        patchOpGeneration: patchOpGeneration,
        postId: arg,
      )) {
        _resolveDiscardedPatchAttempt(
          persistence: persistence,
          postId: arg,
          patchOpGeneration: patchOpGeneration,
          payload: patchPayload,
          requestDispatched: true,
        );
        result = const EditPostSaveDiscarded();
        return result;
      }

      final snap = EditPostSnapshot.fromDetail(updated);
      if (contentEpochAtSave != _editorContentGeneration) {
        persistence.removeRecordIfMatching(arg, patchOpGeneration);
        result = const EditPostSaveDiscarded();
        return result;
      }

      final syncGen = ++_editorContentGeneration;
      _syncAttachmentsAfterEditorSnapshot(snap, editorLoadGeneration: syncGen);

      if (!snap.editable) {
        persistence.removeRecordIfMatching(arg, patchOpGeneration);
        _pendingUncertainPayload = null;
        _lastReconcileObservation = null;
        state = AsyncValue.data(
          EditPostSession(
            snapshot: snap,
            saveSuccessTick: current.saveSuccessTick,
          ),
        );
        return EditPostSaveBlocked(
          snap.blockMessage ??
              'El servidor cambió el estado tras guardar. No continúes editando hasta revisar.',
        );
      }

      persistence.removeRecordIfMatching(arg, patchOpGeneration);
      _pendingUncertainPayload = null;
      _lastReconcileObservation = null;
      state = AsyncValue.data(
        EditPostSession(
          snapshot: snap,
          saveSuccessTick: current.saveSuccessTick + 1,
        ),
      );
      return EditPostSaveSuccess(updated);
    } on ApiFailure catch (e) {
      if (!_patchAttemptStillActive(
        persistence: persistence,
        userId: userId,
        sessionEpoch: epoch,
        saveGeneration: saveGeneration,
        patchOpGeneration: patchOpGeneration,
        postId: arg,
      )) {
        _resolveDiscardedPatchAttempt(
          persistence: persistence,
          postId: arg,
          patchOpGeneration: patchOpGeneration,
          payload: patchPayload,
          requestDispatched: requestDispatched,
        );
        result = const EditPostSaveDiscarded();
        return result;
      }
      if (isEditPostPatchOutcomeUncertain(e)) {
        persistence.promoteToOutcomeUncertainIfMatching(arg, patchOpGeneration);
        _pendingUncertainPayload = patchPayload;
        state = AsyncValue.data(
          current.copyWith(
            saveInFlight: false,
            patchUncertain: true,
            uncertainPhase: EditPostUncertainPatchPhase.outcomeUncertain,
            clearSaveFailure: true,
          ),
        );
        return const EditPostSaveUncertain();
      }
      persistence.removeRecordIfMatching(arg, patchOpGeneration);
      state = AsyncValue.data(
        current.copyWith(
          snapshot: current.snapshot,
          saveInFlight: false,
          saveFailure: e,
          clearUncertainPhase: true,
        ),
      );
      return EditPostSaveFailure(e);
    } catch (_) {
      if (!_patchAttemptStillActive(
        persistence: persistence,
        userId: userId,
        sessionEpoch: epoch,
        saveGeneration: saveGeneration,
        patchOpGeneration: patchOpGeneration,
        postId: arg,
      )) {
        _resolveDiscardedPatchAttempt(
          persistence: persistence,
          postId: arg,
          patchOpGeneration: patchOpGeneration,
          payload: patchPayload,
          requestDispatched: requestDispatched,
        );
        result = const EditPostSaveDiscarded();
        return result;
      }
      persistence.promoteToOutcomeUncertainIfMatching(arg, patchOpGeneration);
      _pendingUncertainPayload = patchPayload;
      state = AsyncValue.data(
        current.copyWith(
          saveInFlight: false,
          patchUncertain: true,
          uncertainPhase: EditPostUncertainPatchPhase.outcomeUncertain,
        ),
      );
      return const EditPostSaveUncertain();
    } finally {
      attachPersistence.releaseExclusive(patchLease);
      if (_activeSaveGeneration == saveGeneration) {
        _activeSaveGeneration = null;
        _activePatchOperationGeneration = null;
      }
      final value = state.valueOrNull;
      if (value != null &&
          value.saveInFlight &&
          saveGeneration == _saveGeneration &&
          persistence.sessionBindingActiveFor(userId, epoch)) {
        state = AsyncValue.data(value.copyWith(saveInFlight: false));
      }
    }
  }

  Future<EditPostReconcileResult> reconcileUncertainPatch() async {
    final current = state.valueOrNull;
    final pending = _pendingUncertainPayload;
    if (current == null || !current.patchUncertain || pending == null) {
      return const EditPostReconcileStillUncertain(
        'No hay un guardado incierto que verificar.',
      );
    }

    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null || epoch != pending.sessionEpoch) {
      return const EditPostReconcileDiscarded();
    }

    final persisted = _patchPersistence.recordFor(arg);
    final opGen =
        persisted?.operationGeneration ?? _activePatchOperationGeneration;
    if (opGen == null) {
      return const EditPostReconcileStillUncertain(
        'No hay un registro del intento guardado.',
      );
    }

    _lastReconcileObservation = null;
    final generation = ++_loadGeneration;
    try {
      final remote = await ref.read(postRepositoryProvider).getPost(arg);
      if (generation != _loadGeneration ||
          neighborhoodSessionEpoch(ref) != epoch) {
        return const EditPostReconcileDiscarded();
      }

      final snap = EditPostSnapshot.fromDetail(remote);
      if (!snap.editable) {
        _patchPersistence.markOutcomeUncertain(arg, opGen);
        state = AsyncValue.data(
          EditPostSession(
            snapshot: snap,
            patchUncertain: true,
            uncertainPhase: EditPostUncertainPatchPhase.outcomeUncertain,
          ),
        );
        final statusNote =
            snap.blockMessage ??
            'El estado en el servidor ya no permite editar.';
        return EditPostReconcileRemoteChanged(
          remote,
          '$statusNote No confirmamos por HTTP si tu último intento de '
          'guardado se aplicó antes de este cambio de estado.',
        );
      }

      final working = remote.workingContent;
      final remoteCategory = remote.category?.id;
      if (working == null) {
        return const EditPostReconcileStillUncertain(
          'No pudimos leer el contenido editable del servidor.',
        );
      }

      final matches = pending.contentMatchesRemote(
        remoteTitle: working.title,
        remoteBody: working.body,
        remoteCategoryId: remoteCategory,
      );

      final reconcileGen = ++_reconcileGeneration;
      _lastReconcileObservation = EditPostReconcileObservation(
        remote: remote,
        operationGeneration: opGen,
        reconcileGeneration: reconcileGen,
        contentMatchesPending: matches,
      );

      if (matches) {
        return const EditPostReconcileObservableMatch(
          'El servidor contiene los cambios consultados, pero no podemos '
          'confirmar qué solicitud los guardó. El resultado del último '
          'guardado sigue siendo incierto hasta una respuesta HTTP confirmada '
          'o una nueva acción explícita.',
        );
      }

      return const EditPostReconcileRemoteConflict(
        'El servidor tiene una versión distinta a la de tu último intento '
        'de guardado. Conservamos tu texto local; revisa antes de volver a guardar.',
      );
    } on ApiFailure catch (e) {
      if (generation != _loadGeneration) {
        return const EditPostReconcileDiscarded();
      }
      _lastReconcileObservation = null;
      return EditPostReconcileStillUncertain(e.userMessage);
    } catch (_) {
      if (generation != _loadGeneration) {
        return const EditPostReconcileDiscarded();
      }
      _lastReconcileObservation = null;
      return const EditPostReconcileStillUncertain(
        'No pudimos consultar el servidor. Intenta verificar más tarde.',
      );
    }
  }

  bool _formMatchesServerSnapshot({
    required EditPostSnapshot snap,
    required int categoryId,
    required String title,
    required String body,
  }) {
    final working = snap.detail.workingContent;
    if (working == null) {
      return false;
    }
    return working.title.trim() == title.trim() &&
        working.body.trim() == body.trim() &&
        snap.detail.category?.id == categoryId;
  }

  bool _submitAttemptStillActive({
    required int operationGeneration,
    required int userId,
    required int sessionEpoch,
    required int submitGeneration,
  }) {
    if (submitGeneration != _submitGeneration) {
      return false;
    }
    if (!_submitPersistence.sessionBindingActiveFor(userId, sessionEpoch)) {
      return false;
    }
    final record = _submitPersistence.peekRecordForPost(arg);
    if (record == null) {
      return false;
    }
    return record.operationGeneration == operationGeneration;
  }

  Future<EditPostSubmitResult> submitToModeration({
    required int categoryId,
    required String title,
    required String body,
  }) async {
    final current = state.valueOrNull;
    if (current == null) {
      return const EditPostSubmitBlocked(
        'Aún cargamos la publicación. Espera un momento.',
      );
    }
    if (_activeSubmitGeneration != null || current.submitInFlight) {
      return const EditPostSubmitInFlight();
    }
    if (current.submitUncertain) {
      return const EditPostSubmitBlocked(
        'Hay un envío con resultado incierto. Verifica el estado antes de enviar de nuevo.',
      );
    }
    if (current.patchUncertain ||
        _patchPersistence.peekRecordForPost(arg) != null) {
      return const EditPostSubmitBlocked(
        'Hay un guardado incierto. Resuélvelo antes de enviar a revisión.',
      );
    }
    if (_activeSaveGeneration != null || current.saveInFlight) {
      return const EditPostSubmitBlocked(
        'Hay un guardado en curso. Espera a que termine.',
      );
    }

    final attachState = ref.read(editPostAttachmentsControllerProvider(arg));
    final attachPersistence = ref.read(
      editPostAttachmentsPersistenceProvider.notifier,
    );
    if (attachPersistence.blocksSubmitForPost(arg)) {
      return const EditPostSubmitBlocked(
        'Hay otra operación en curso en esta publicación.',
      );
    }
    if (attachState.blocksContentSave) {
      return const EditPostSubmitBlocked(
        'Hay adjuntos subiendo o con resultado incierto. Resuélvelo antes de enviar.',
      );
    }
    if (attachState.needsUpload.isNotEmpty) {
      return const EditPostSubmitBlocked(
        'Hay archivos seleccionados sin subir. Complétalo o quítalos antes de enviar.',
      );
    }
    if (attachState.revisionSyncInFlight) {
      return const EditPostSubmitBlocked(
        'Estamos sincronizando la revisión editable. Intenta de nuevo en un momento.',
      );
    }

    final snap = current.snapshot;
    final status = snap.detail.status;
    if (status != 'draft' && status != 'rejected') {
      return const EditPostSubmitBlocked(
        'Solo puedes enviar borradores o publicaciones rechazadas.',
      );
    }
    if (!snap.editable) {
      return EditPostSubmitBlocked(
        snap.blockMessage ?? 'Esta publicación no se puede enviar ahora.',
      );
    }
    if (!_formMatchesServerSnapshot(
      snap: snap,
      categoryId: categoryId,
      title: title,
      body: body,
    )) {
      return const EditPostSubmitBlocked(
        'Tienes cambios sin guardar. Guarda antes de enviar a revisión.',
      );
    }

    final revisionId = snap.editableRevisionId;
    if (revisionId == null) {
      return const EditPostSubmitBlocked(
        'No hay una revisión editable confirmada.',
      );
    }

    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return const EditPostSubmitDiscarded();
    }
    final userId = _authenticatedUserId();
    if (userId == null) {
      return const EditPostSubmitDiscarded();
    }

    final contentEpochAtSubmit = _editorContentGeneration;
    final lease = attachPersistence.tryAcquireExclusive(
      userId: userId,
      sessionEpoch: epoch,
      postId: arg,
      kind: EditPostExclusiveOperationKind.submit,
    );
    if (lease == null) {
      return const EditPostSubmitBlocked(
        'Hay otra operación en curso (guardado, subida o envío).',
      );
    }

    final opGeneration = _submitPersistence.beginSubmitAttempt(
      userId: userId,
      sessionEpoch: epoch,
      postId: arg,
      revisionId: revisionId,
    );
    if (opGeneration == null) {
      attachPersistence.releaseExclusive(lease);
      return const EditPostSubmitBlocked(
        'No pudimos registrar el envío de forma segura.',
      );
    }

    final submitGeneration = ++_submitGeneration;
    _activeSubmitGeneration = submitGeneration;
    _pendingUncertainSubmit = EditPostSubmitPayload(
      postId: arg,
      revisionId: revisionId,
      sessionEpoch: epoch,
      operationGeneration: opGeneration,
    );

    state = AsyncValue.data(
      current.copyWith(submitInFlight: true, clearSubmitFailure: true),
    );

    try {
      final updated = await ref.read(postRepositoryProvider).submitPost(arg);

      if (!_submitAttemptStillActive(
        operationGeneration: opGeneration,
        userId: userId,
        sessionEpoch: epoch,
        submitGeneration: submitGeneration,
      )) {
        _submitPersistence.promoteToOutcomeUncertainIfMatching(
          arg,
          opGeneration,
        );
        return const EditPostSubmitDiscarded();
      }

      if (contentEpochAtSubmit != _editorContentGeneration) {
        _submitPersistence.removeRecordIfMatching(arg, opGeneration);
        _pendingUncertainSubmit = null;
        return const EditPostSubmitDiscarded();
      }

      if (updated.status != 'pending') {
        _submitPersistence.removeRecordIfMatching(arg, opGeneration);
        _pendingUncertainSubmit = null;
        return const EditPostSubmitBlocked(
          'El servidor no devolvió el estado esperado tras el envío.',
        );
      }

      _submitPersistence.removeRecordIfMatching(arg, opGeneration);
      _pendingUncertainSubmit = null;
      final nextSnap = EditPostSnapshot.fromDetail(updated);
      final syncGen = ++_editorContentGeneration;
      _syncAttachmentsAfterEditorSnapshot(
        nextSnap,
        editorLoadGeneration: syncGen,
      );
      state = AsyncValue.data(EditPostSession(snapshot: nextSnap));
      ref.invalidate(myPostsControllerProvider);
      return EditPostSubmitSuccess(updated);
    } on ApiFailure catch (e) {
      if (!_submitAttemptStillActive(
        operationGeneration: opGeneration,
        userId: userId,
        sessionEpoch: epoch,
        submitGeneration: submitGeneration,
      )) {
        return const EditPostSubmitDiscarded();
      }
      if (isEditPostSubmitOutcomeUncertain(e)) {
        _submitPersistence.promoteToOutcomeUncertainIfMatching(
          arg,
          opGeneration,
        );
        state = AsyncValue.data(
          current.copyWith(
            submitInFlight: false,
            submitUncertain: true,
            submitUncertainPhase: EditPostUncertainSubmitPhase.outcomeUncertain,
            clearSubmitFailure: true,
          ),
        );
        return const EditPostSubmitUncertain();
      }
      _submitPersistence.removeRecordIfMatching(arg, opGeneration);
      _pendingUncertainSubmit = null;
      state = AsyncValue.data(
        current.copyWith(
          submitInFlight: false,
          submitFailure: e,
          clearSubmitUncertainPhase: true,
        ),
      );
      return EditPostSubmitFailure(e);
    } catch (_) {
      if (!_submitAttemptStillActive(
        operationGeneration: opGeneration,
        userId: userId,
        sessionEpoch: epoch,
        submitGeneration: submitGeneration,
      )) {
        return const EditPostSubmitDiscarded();
      }
      _submitPersistence.promoteToOutcomeUncertainIfMatching(arg, opGeneration);
      state = AsyncValue.data(
        current.copyWith(
          submitInFlight: false,
          submitUncertain: true,
          submitUncertainPhase: EditPostUncertainSubmitPhase.outcomeUncertain,
        ),
      );
      return const EditPostSubmitUncertain();
    } finally {
      attachPersistence.releaseExclusive(lease);
      if (_activeSubmitGeneration == submitGeneration) {
        _activeSubmitGeneration = null;
      }
      final value = state.valueOrNull;
      if (value != null &&
          value.submitInFlight &&
          submitGeneration == _submitGeneration) {
        state = AsyncValue.data(value.copyWith(submitInFlight: false));
      }
    }
  }

  Future<EditPostSubmitReconcileResult> reconcileUncertainSubmit() async {
    final current = state.valueOrNull;
    if (current == null || !current.submitUncertain) {
      return const EditPostSubmitReconcileStillUncertain(
        'No hay un envío incierto que verificar.',
      );
    }
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return const EditPostSubmitReconcileDiscarded();
    }
    final generation = ++_loadGeneration;
    try {
      final remote = await ref.read(postRepositoryProvider).getPost(arg);
      if (generation != _loadGeneration ||
          neighborhoodSessionEpoch(ref) != epoch) {
        return const EditPostSubmitReconcileDiscarded();
      }
      final snap = EditPostSnapshot.fromDetail(remote);
      if (remote.status == 'pending') {
        state = AsyncValue.data(
          EditPostSession(
            snapshot: snap,
            submitUncertain: true,
            submitUncertainPhase:
                current.submitUncertainPhase ??
                EditPostUncertainSubmitPhase.outcomeUncertain,
          ),
        );
        return EditPostSubmitReconcileObservedPending(
          remote,
          'La publicación está en moderación en el servidor. '
          'Eso no confirma por HTTP que tu último envío fue el que la dejó así.',
        );
      }
      if (snap.editable) {
        state = AsyncValue.data(current.copyWith(snapshot: snap));
        return const EditPostSubmitReconcileStillUncertain(
          'Sigue editable como borrador o rechazada; no confirmamos el envío anterior.',
        );
      }
      state = AsyncValue.data(EditPostSession(snapshot: snap));
      return EditPostSubmitReconcileObservedPending(
        remote,
        'El estado remoto cambió. Revisa si corresponde a tu envío.',
      );
    } on ApiFailure catch (e) {
      return EditPostSubmitReconcileGetFailed(e);
    }
  }

  /// Adopción explícita del último GET de reconciliación (no afirma éxito del PATCH).
  EditPostAdoptResult adoptObservedServerState() {
    final current = state.valueOrNull;
    final pending = _pendingUncertainPayload;
    final observation = _lastReconcileObservation;
    final epoch = neighborhoodSessionEpoch(ref);

    if (epoch == null) {
      return const EditPostAdoptDiscarded();
    }
    if (current == null || !current.patchUncertain || pending == null) {
      return const EditPostAdoptBlocked(
        'No hay un guardado incierto que resolver.',
      );
    }
    if (observation == null) {
      return const EditPostAdoptBlocked(
        'Primero verifica el estado en el servidor.',
      );
    }
    if (observation.reconcileGeneration != _reconcileGeneration) {
      return const EditPostAdoptBlocked(
        'La observación del servidor ya no es válida. Vuelve a verificar.',
      );
    }

    final record = _patchPersistence.recordFor(arg);
    if (record == null ||
        record.operationGeneration != observation.operationGeneration) {
      return const EditPostAdoptBlocked(
        'El registro del intento ya no coincide con la verificación actual.',
      );
    }
    if (record.postId != arg ||
        record.revisionId != pending.revisionId ||
        record.userId != _authenticatedUserId()) {
      return const EditPostAdoptBlocked(
        'La adopción no coincide con esta publicación o sesión.',
      );
    }

    final remote = observation.remote;
    if (remote.id != arg) {
      return const EditPostAdoptBlocked(
        'La observación pertenece a otra publicación.',
      );
    }

    final snap = EditPostSnapshot.fromDetail(remote);
    if (!snap.editable) {
      return const EditPostAdoptBlocked(
        'El servidor ya no permite editar esta publicación.',
      );
    }
    final remoteRevision = snap.editableRevisionId;
    if (remoteRevision == null || remoteRevision != pending.revisionId) {
      return const EditPostAdoptBlocked(
        'La revisión en el servidor no coincide con el intento guardado.',
      );
    }

    _patchPersistence.clearAfterAdopt(arg, observation.operationGeneration);
    _pendingUncertainPayload = null;
    _lastReconcileObservation = null;
    state = AsyncValue.data(
      EditPostSession(
        snapshot: snap,
        patchUncertain: false,
        saveSuccessTick: current.saveSuccessTick,
      ),
    );
    return EditPostAdoptSuccess(remote);
  }
}

final editPostControllerProvider = AutoDisposeAsyncNotifierProvider.family<
  EditPostController,
  EditPostSession,
  int
>(EditPostController.new);
