import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import '../data/models/post_category.dart';
import '../data/models/post_detail.dart';
import '../data/post_repository.dart';
import 'create_post_session_persistence.dart';

enum CreatePostPhase { idle, submitting, submitted }

class CreatePostWorkflowState {
  const CreatePostWorkflowState({
    this.phase = CreatePostPhase.idle,
    this.confirmedDraftId,
    this.uncertainCreate = false,
  });

  final CreatePostPhase phase;
  final int? confirmedDraftId;
  final bool uncertainCreate;

  bool get hasDraftAwaitingSubmit => confirmedDraftId != null;

  /// Bloquea un nuevo POST /posts mientras no haya ID confirmado ni recuperación explícita.
  bool get blocksFullSend => uncertainCreate && confirmedDraftId == null;

  CreatePostWorkflowState copyWith({
    CreatePostPhase? phase,
    int? confirmedDraftId,
    bool? uncertainCreate,
    bool clearDraftId = false,
    bool clearUncertain = false,
  }) {
    return CreatePostWorkflowState(
      phase: phase ?? this.phase,
      confirmedDraftId:
          clearDraftId ? null : (confirmedDraftId ?? this.confirmedDraftId),
      uncertainCreate:
          clearUncertain ? false : (uncertainCreate ?? this.uncertainCreate),
    );
  }
}

sealed class CreatePostSendResult {
  const CreatePostSendResult();
}

class CreatePostSendSuccess extends CreatePostSendResult {
  const CreatePostSendSuccess(this.detail);

  final PostDetail detail;
}

class CreatePostSendDiscarded extends CreatePostSendResult {
  const CreatePostSendDiscarded();
}

class CreatePostSendInFlight extends CreatePostSendResult {
  const CreatePostSendInFlight();
}

class CreatePostSendNoSession extends CreatePostSendResult {
  const CreatePostSendNoSession();
}

class CreatePostSendCreateFailed extends CreatePostSendResult {
  const CreatePostSendCreateFailed(this.failure);

  final ApiFailure failure;
}

class CreatePostSendDraftOnly extends CreatePostSendResult {
  const CreatePostSendDraftOnly(this.draftId, this.failure);

  final int draftId;
  final ApiFailure failure;
}

class CreatePostSendUncertain extends CreatePostSendResult {
  const CreatePostSendUncertain();
}

class CreatePostSendDraftLinked extends CreatePostSendResult {
  const CreatePostSendDraftLinked(this.draftId);

  final int draftId;
}

class CreatePostSendAlreadyPending extends CreatePostSendResult {
  const CreatePostSendAlreadyPending(this.detail);

  final PostDetail detail;
}

class CreatePostController
    extends AutoDisposeNotifier<CreatePostWorkflowState> {
  bool _submitInFlight = false;
  int _submitGeneration = 0;
  int? _trackedSessionEpoch;
  CreatePostPhase _uiPhase = CreatePostPhase.idle;

  CreatePostSessionPersistenceState get _sessionPersistence =>
      ref.read(createPostSessionPersistenceProvider);

  @override
  CreatePostWorkflowState build() {
    final epoch = ref.watch(createPostSessionEpochProvider);
    final persisted = ref.read(createPostSessionPersistenceProvider);
    if (epoch == null) {
      _trackedSessionEpoch = null;
      _submitInFlight = false;
      _uiPhase = CreatePostPhase.idle;
      return const CreatePostWorkflowState();
    }

    if (_trackedSessionEpoch != epoch) {
      _trackedSessionEpoch = epoch;
      _submitInFlight = false;
      _submitGeneration++;
      _uiPhase = CreatePostPhase.idle;
      return _hydrateFromPersistence(persisted, _uiPhase);
    }

    return _hydrateFromPersistence(persisted, _uiPhase);
  }

  void _setWorkflow(CreatePostWorkflowState next) {
    _uiPhase = next.phase;
    state = next;
  }

  CreatePostWorkflowState _hydrateFromPersistence(
    CreatePostSessionPersistenceState persisted,
    CreatePostPhase phase,
  ) {
    return CreatePostWorkflowState(
      phase: phase,
      confirmedDraftId: persisted.confirmedDraftId,
      uncertainCreate: persisted.uncertainCreate,
    );
  }

  void _persistUncertain() {
    ref
        .read(createPostSessionPersistenceProvider.notifier)
        .markUncertainCreate();
  }

  void _persistDraftId(int id, {required bool clearUncertain}) {
    ref
        .read(createPostSessionPersistenceProvider.notifier)
        .setConfirmedDraftId(id, clearUncertain: clearUncertain);
  }

  void _persistClearAll() {
    ref.read(createPostSessionPersistenceProvider.notifier).clearAll();
  }

  void releaseStaleSubmitUi() {
    if (_uiPhase == CreatePostPhase.submitting) {
      _setWorkflow(
        _hydrateFromPersistence(_sessionPersistence, CreatePostPhase.idle),
      );
    }
    _submitInFlight = false;
  }

  void resetAfterSuccess() {
    _persistClearAll();
    _uiPhase = CreatePostPhase.idle;
    _setWorkflow(const CreatePostWorkflowState());
    ++_submitGeneration;
  }

  Future<CreatePostSendResult> sendForReview({
    required int neighborhoodGroupId,
    required int categoryId,
    required String title,
    required String body,
  }) async {
    if (_submitInFlight) {
      return const CreatePostSendInFlight();
    }

    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return const CreatePostSendNoSession();
    }

    final persisted = _sessionPersistence;
    if (persisted.blocksFullSend) {
      return const CreatePostSendUncertain();
    }

    final existingDraftId =
        persisted.confirmedDraftId ?? state.confirmedDraftId;
    if (existingDraftId != null) {
      return _submitOnly(postId: existingDraftId, epoch: epoch);
    }

    final generation = ++_submitGeneration;
    _submitInFlight = true;
    _setWorkflow(
      _hydrateFromPersistence(_sessionPersistence, CreatePostPhase.submitting),
    );

    try {
      final created = await ref
          .read(postRepositoryProvider)
          .createCommunityPost(
            neighborhoodGroupId: neighborhoodGroupId,
            categoryId: categoryId,
            title: title,
            body: body,
          );

      if (!_stillSameSession(epoch, generation)) {
        return const CreatePostSendDiscarded();
      }

      _persistDraftId(created.id, clearUncertain: true);
      _setWorkflow(
        CreatePostWorkflowState(phase: _uiPhase, confirmedDraftId: created.id),
      );

      return await _submitOnly(
        postId: created.id,
        epoch: epoch,
        generation: generation,
        skipGenerationBump: true,
      );
    } on ApiFailure catch (e) {
      if (!_stillSameSession(epoch, generation)) {
        return const CreatePostSendDiscarded();
      }

      final draftId =
          _sessionPersistence.confirmedDraftId ?? state.confirmedDraftId;
      if (draftId != null) {
        _setWorkflow(
          _hydrateFromPersistence(_sessionPersistence, CreatePostPhase.idle),
        );
        return CreatePostSendDraftOnly(draftId, e);
      }

      _setWorkflow(
        _hydrateFromPersistence(_sessionPersistence, CreatePostPhase.idle),
      );
      return CreatePostSendCreateFailed(e);
    } catch (_) {
      if (!_stillSameSession(epoch, generation)) {
        return const CreatePostSendDiscarded();
      }

      _persistUncertain();
      _setWorkflow(
        _hydrateFromPersistence(_sessionPersistence, CreatePostPhase.idle),
      );
      return const CreatePostSendUncertain();
    } finally {
      _submitInFlight = false;
    }
  }

  Future<CreatePostSendResult> retrySubmitOnly() async {
    final draftId =
        _sessionPersistence.confirmedDraftId ?? state.confirmedDraftId;
    if (draftId == null) {
      return const CreatePostSendCreateFailed(ApiUnexpectedFailure());
    }

    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return const CreatePostSendNoSession();
    }

    return _submitOnly(postId: draftId, epoch: epoch);
  }

  Future<CreatePostSendResult> refreshDraftStatusAndMaybeSubmit() async {
    final draftId =
        _sessionPersistence.confirmedDraftId ?? state.confirmedDraftId;
    if (draftId == null) {
      return const CreatePostSendCreateFailed(ApiUnexpectedFailure());
    }

    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return const CreatePostSendNoSession();
    }

    final generation = ++_submitGeneration;

    try {
      final detail = await ref.read(postRepositoryProvider).getPost(draftId);
      if (!_stillSameSession(epoch, generation)) {
        return const CreatePostSendDiscarded();
      }

      if (detail.status == 'pending') {
        _persistClearAll();
        _setWorkflow(
          const CreatePostWorkflowState(phase: CreatePostPhase.submitted),
        );
        return CreatePostSendSuccess(detail);
      }

      if (detail.status == 'draft' || detail.status == 'rejected') {
        return _submitOnly(
          postId: draftId,
          epoch: epoch,
          generation: generation,
        );
      }

      _setWorkflow(
        _hydrateFromPersistence(_sessionPersistence, CreatePostPhase.idle),
      );
      return CreatePostSendSuccess(detail);
    } on ApiFailure catch (e) {
      if (neighborhoodSessionEpoch(ref) != epoch) {
        return const CreatePostSendDiscarded();
      }
      return CreatePostSendCreateFailed(e);
    }
  }

  /// Enlaza un borrador elegido explícitamente tras un create incierto (sin auto-selección).
  Future<CreatePostSendResult> linkExplicitRecoveryDraft(int postId) async {
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return const CreatePostSendNoSession();
    }

    final confirmed =
        _sessionPersistence.confirmedDraftId ?? state.confirmedDraftId;
    if (confirmed != null && confirmed != postId) {
      return const CreatePostSendCreateFailed(ApiUnexpectedFailure());
    }

    final generation = ++_submitGeneration;

    try {
      final detail = await ref.read(postRepositoryProvider).getPost(postId);
      if (!_stillSameSession(epoch, generation)) {
        return const CreatePostSendDiscarded();
      }

      if (detail.status == 'pending') {
        _setWorkflow(
          _hydrateFromPersistence(_sessionPersistence, CreatePostPhase.idle),
        );
        return CreatePostSendAlreadyPending(detail);
      }

      if (detail.status != 'draft' && detail.status != 'rejected') {
        return const CreatePostSendCreateFailed(ApiUnexpectedFailure());
      }

      _persistDraftId(postId, clearUncertain: true);
      _setWorkflow(
        CreatePostWorkflowState(
          phase: CreatePostPhase.idle,
          confirmedDraftId: postId,
        ),
      );
      return CreatePostSendDraftLinked(postId);
    } on ApiFailure catch (e) {
      if (neighborhoodSessionEpoch(ref) != epoch) {
        return const CreatePostSendDiscarded();
      }
      return CreatePostSendCreateFailed(e);
    }
  }

  Future<CreatePostSendResult> _submitOnly({
    required int postId,
    required int epoch,
    int? generation,
    bool skipGenerationBump = false,
  }) async {
    if (_submitInFlight && !skipGenerationBump) {
      return const CreatePostSendInFlight();
    }

    final submitGeneration = generation ?? ++_submitGeneration;
    if (generation == null) {
      _submitInFlight = true;
      _setWorkflow(
        _hydrateFromPersistence(
          _sessionPersistence,
          CreatePostPhase.submitting,
        ),
      );
    }

    try {
      final submitted = await ref
          .read(postRepositoryProvider)
          .submitPost(postId);

      if (!_stillSameSession(epoch, submitGeneration)) {
        return const CreatePostSendDiscarded();
      }

      if (submitted.status == 'pending' || submitted.status == 'published') {
        _persistClearAll();
        _setWorkflow(
          const CreatePostWorkflowState(phase: CreatePostPhase.submitted),
        );
        return CreatePostSendSuccess(submitted);
      }

      _persistDraftId(postId, clearUncertain: true);
      _setWorkflow(
        CreatePostWorkflowState(
          phase: CreatePostPhase.idle,
          confirmedDraftId: postId,
        ),
      );
      return CreatePostSendSuccess(submitted);
    } on ApiFailure catch (e) {
      if (!_stillSameSession(epoch, submitGeneration)) {
        return const CreatePostSendDiscarded();
      }
      _persistDraftId(postId, clearUncertain: false);
      _setWorkflow(
        CreatePostWorkflowState(
          phase: CreatePostPhase.idle,
          confirmedDraftId: postId,
        ),
      );
      return CreatePostSendDraftOnly(postId, e);
    } finally {
      if (generation == null) {
        _submitInFlight = false;
      }
    }
  }

  bool _stillSameSession(int epoch, int generation) {
    return neighborhoodSessionEpoch(ref) == epoch &&
        generation == _submitGeneration;
  }
}

final postCategoriesProvider = FutureProvider.autoDispose<List<PostCategory>>((
  ref,
) async {
  ref.watch(authControllerProvider);
  final auth = ref.read(authControllerProvider);
  if (auth is! AuthAuthenticated) {
    return const [];
  }
  final epoch = neighborhoodSessionEpoch(ref);
  if (epoch == null) {
    return const [];
  }
  final categories = await ref
      .read(postRepositoryProvider)
      .listPostCategories(audience: 'group');
  if (neighborhoodSessionEpoch(ref) != epoch) {
    throw const ApiSessionExpiredFailure();
  }
  return categories;
});

final createPostSessionEpochProvider = Provider.autoDispose<int?>((ref) {
  ref.watch(authControllerProvider);
  return neighborhoodSessionEpoch(ref);
});

final createPostControllerProvider =
    NotifierProvider.autoDispose<CreatePostController, CreatePostWorkflowState>(
      CreatePostController.new,
    );

bool isNeighborhoodGroupEligibleForPosting(String status) => status == 'active';
