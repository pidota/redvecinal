import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import '../data/post_report_outcome_store.dart';
import 'post_report_outcome.dart';

class PostReportCoordinatorState {
  const PostReportCoordinatorState({
    this.records = const {},
    this.hydrated = false,
    this.persistUnavailable = false,
  });

  final Map<String, PostReportOutcomeRecord> records;
  final bool hydrated;
  final bool persistUnavailable;

  PostReportOutcomeRecord? recordFor(int userId, int postId) {
    return records['$userId:$postId'];
  }
}

/// Coordinador compartido de exclusión y persistencia (no autoDispose).
///
/// La clave es usuario + publicación. Un usuario no bloquea a otro.
/// `confirming` y `persistBlocked` solo viven en memoria.
/// Tras reinicio, un `inFlight` se trata como `uncertain` (el POST pudo completarse).
class PostReportCoordinator extends Notifier<PostReportCoordinatorState> {
  int _nextGeneration = 1;
  Future<void>? _hydrateFuture;
  Future<bool> _persistChain = Future<bool>.value(true);

  @override
  PostReportCoordinatorState build() {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      _dropConfirmingRecords();
    });
    return const PostReportCoordinatorState();
  }

  Future<void> ensureHydrated() {
    final existing = _hydrateFuture;
    if (existing != null) {
      return existing;
    }
    final future = _hydrate();
    _hydrateFuture = future;
    return future;
  }

  Future<void> _hydrate() async {
    try {
      final loaded = await ref.read(postReportOutcomeStoreProvider).loadAll();
      final mapped = <String, PostReportOutcomeRecord>{};
      var convertedUncertain = false;
      for (final record in loaded) {
        final normalized =
            record.status == PostReportOutcomeStatus.inFlight
                ? record.copyWith(status: PostReportOutcomeStatus.uncertain)
                : record;
        if (normalized.status == PostReportOutcomeStatus.uncertain &&
            record.status == PostReportOutcomeStatus.inFlight) {
          convertedUncertain = true;
        }
        mapped[normalized.storageKey] = normalized;
      }
      for (final current in state.records.values) {
        final disk = mapped[current.storageKey];
        if (disk != null) {
          continue;
        }
        if (current.status == PostReportOutcomeStatus.confirming ||
            current.status == PostReportOutcomeStatus.inFlight ||
            current.status == PostReportOutcomeStatus.persistBlocked) {
          mapped[current.storageKey] = current;
        }
      }
      state = PostReportCoordinatorState(records: mapped, hydrated: true);
      if (convertedUncertain) {
        await _enqueuePersist();
      }
    } on Object {
      state = const PostReportCoordinatorState(
        hydrated: true,
        persistUnavailable: true,
      );
    }
  }

  PostReportOutcomeRecord? recordFor(int userId, int postId) {
    return state.recordFor(userId, postId);
  }

  bool tryBeginConfirming({required int userId, required int postId}) {
    if (!state.hydrated || state.persistUnavailable) {
      return false;
    }
    final existing = state.recordFor(userId, postId);
    if (existing != null) {
      return false;
    }
    final record = PostReportOutcomeRecord(
      userId: userId,
      postId: postId,
      status: PostReportOutcomeStatus.confirming,
      generation: _nextGeneration++,
      recordedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    _put(record);
    return true;
  }

  void cancelConfirming({required int userId, required int postId}) {
    final existing = state.recordFor(userId, postId);
    if (existing == null ||
        existing.status != PostReportOutcomeStatus.confirming) {
      return;
    }
    _remove(existing.storageKey);
  }

  /// Transición `confirming → inFlight` persistida **antes** del POST.
  Future<int?> beginInFlight({required int userId, required int postId}) async {
    if (!state.hydrated || state.persistUnavailable) {
      return null;
    }
    final existing = state.recordFor(userId, postId);
    if (existing == null ||
        existing.status != PostReportOutcomeStatus.confirming) {
      return null;
    }
    final next = existing.copyWith(
      status: PostReportOutcomeStatus.inFlight,
      recordedAtMillis: DateTime.now().millisecondsSinceEpoch,
    );
    _put(next);
    final persisted = await _enqueuePersist();
    if (!persisted) {
      _put(next.copyWith(status: PostReportOutcomeStatus.persistBlocked));
      return null;
    }
    if (!matchesGeneration(
      userId: userId,
      postId: postId,
      generation: next.generation,
    )) {
      return null;
    }
    return next.generation;
  }

  Future<bool> markConfirmed({
    required int userId,
    required int postId,
    required int generation,
  }) {
    return _persistOutcome(
      userId: userId,
      postId: postId,
      generation: generation,
      status: PostReportOutcomeStatus.confirmed,
    );
  }

  Future<bool> markUncertain({
    required int userId,
    required int postId,
    required int generation,
  }) {
    return _persistOutcome(
      userId: userId,
      postId: postId,
      generation: generation,
      status: PostReportOutcomeStatus.uncertain,
    );
  }

  Future<void> releaseInFlight({
    required int userId,
    required int postId,
    required int generation,
  }) async {
    final existing = state.recordFor(userId, postId);
    if (existing == null ||
        existing.generation != generation ||
        existing.status != PostReportOutcomeStatus.inFlight) {
      return;
    }
    _remove(existing.storageKey);
    await _enqueuePersist();
  }

  bool matchesGeneration({
    required int userId,
    required int postId,
    required int generation,
  }) {
    final existing = state.recordFor(userId, postId);
    return existing != null && existing.generation == generation;
  }

  Future<bool> _persistOutcome({
    required int userId,
    required int postId,
    required int generation,
    required PostReportOutcomeStatus status,
  }) async {
    final existing = state.recordFor(userId, postId);
    if (existing == null || existing.generation != generation) {
      return false;
    }
    _put(
      existing.copyWith(
        status: status,
        recordedAtMillis: DateTime.now().millisecondsSinceEpoch,
      ),
    );
    final persisted = await _enqueuePersist();
    if (persisted) {
      return true;
    }
    if (status != PostReportOutcomeStatus.uncertain) {
      final still = state.recordFor(userId, postId);
      if (still != null && still.generation == generation) {
        _put(still.copyWith(status: PostReportOutcomeStatus.uncertain));
        await _enqueuePersist();
      }
    }
    return false;
  }

  void _dropConfirmingRecords() {
    final confirming =
        state.records.values
            .where(
              (record) => record.status == PostReportOutcomeStatus.confirming,
            )
            .toList();
    if (confirming.isEmpty) {
      return;
    }
    final next = Map<String, PostReportOutcomeRecord>.from(state.records);
    for (final record in confirming) {
      next.remove(record.storageKey);
    }
    state = PostReportCoordinatorState(
      records: next,
      hydrated: state.hydrated,
      persistUnavailable: state.persistUnavailable,
    );
  }

  void _put(PostReportOutcomeRecord record) {
    final next = Map<String, PostReportOutcomeRecord>.from(state.records)
      ..[record.storageKey] = record;
    state = PostReportCoordinatorState(
      records: next,
      hydrated: state.hydrated,
      persistUnavailable: state.persistUnavailable,
    );
  }

  void _remove(String key) {
    final next = Map<String, PostReportOutcomeRecord>.from(state.records)
      ..remove(key);
    state = PostReportCoordinatorState(
      records: next,
      hydrated: state.hydrated,
      persistUnavailable: state.persistUnavailable,
    );
  }

  Future<bool> _enqueuePersist() {
    final next = _persistChain.then((_) async {
      try {
        final persistable =
            state.records.values
                .where(
                  (record) =>
                      record.status != PostReportOutcomeStatus.confirming &&
                      record.status != PostReportOutcomeStatus.persistBlocked,
                )
                .toList();
        await ref.read(postReportOutcomeStoreProvider).saveAll(persistable);
        return true;
      } on Object {
        return false;
      }
    });
    _persistChain = next;
    return next;
  }
}

final postReportCoordinatorProvider =
    NotifierProvider<PostReportCoordinator, PostReportCoordinatorState>(
      PostReportCoordinator.new,
    );
