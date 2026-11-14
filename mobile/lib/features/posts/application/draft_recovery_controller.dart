import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import '../data/models/feed_post.dart';
import '../data/post_repository.dart';

/// Candidato mostrado solo para revisión manual; no implica correlación con un POST perdido.
class DraftRecoveryCandidate {
  const DraftRecoveryCandidate({
    required this.id,
    required this.status,
    required this.title,
  });

  factory DraftRecoveryCandidate.fromFeedPost(FeedPost post) {
    return DraftRecoveryCandidate(
      id: post.id,
      status: post.status,
      title: post.content?.title ?? 'Sin título',
    );
  }

  final int id;
  final String status;
  final String title;
}

class DraftRecoveryBrowseState {
  const DraftRecoveryBrowseState({
    this.candidates = const [],
    this.nextPageToLoad = 1,
    this.lastPage = 1,
    this.isLoading = false,
    this.allPagesLoaded = false,
    this.failure,
  });

  final List<DraftRecoveryCandidate> candidates;
  final int nextPageToLoad;
  final int lastPage;
  final bool isLoading;
  final bool allPagesLoaded;
  final Object? failure;

  bool get hasMore => !allPagesLoaded && nextPageToLoad <= lastPage;

  /// Hay borradores visibles o aún pueden existir en páginas no cargadas.
  bool get mayHaveUncapturedDrafts => candidates.isNotEmpty || hasMore;

  DraftRecoveryBrowseState copyWith({
    List<DraftRecoveryCandidate>? candidates,
    int? nextPageToLoad,
    int? lastPage,
    bool? isLoading,
    bool? allPagesLoaded,
    Object? failure,
    bool clearFailure = false,
  }) {
    return DraftRecoveryBrowseState(
      candidates: candidates ?? this.candidates,
      nextPageToLoad: nextPageToLoad ?? this.nextPageToLoad,
      lastPage: lastPage ?? this.lastPage,
      isLoading: isLoading ?? this.isLoading,
      allPagesLoaded: allPagesLoaded ?? this.allPagesLoaded,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

class DraftRecoveryController
    extends AutoDisposeNotifier<DraftRecoveryBrowseState> {
  int _loadGeneration = 0;

  @override
  DraftRecoveryBrowseState build() {
    ref.watch(authControllerProvider);
    return const DraftRecoveryBrowseState();
  }

  void reset() {
    _loadGeneration++;
    state = const DraftRecoveryBrowseState();
  }

  Future<void> loadNextPage() async {
    if (state.isLoading) {
      return;
    }
    if (state.allPagesLoaded) {
      return;
    }
    if (state.nextPageToLoad > state.lastPage && state.nextPageToLoad > 1) {
      state = state.copyWith(allPagesLoaded: true);
      return;
    }

    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return;
    }

    final page = state.nextPageToLoad;
    final generation = ++_loadGeneration;

    state = state.copyWith(isLoading: true, clearFailure: true);

    try {
      final result = await ref
          .read(postRepositoryProvider)
          .listMyPosts(page: page);

      if (neighborhoodSessionEpoch(ref) != epoch ||
          generation != _loadGeneration) {
        state = state.copyWith(isLoading: false);
        return;
      }

      final merged = _mergeDraftCandidates(state.candidates, result.items);
      final exhausted = page >= result.lastPage;

      state = DraftRecoveryBrowseState(
        candidates: merged,
        nextPageToLoad: page + 1,
        lastPage: result.lastPage,
        isLoading: false,
        allPagesLoaded: exhausted,
      );
    } on Object catch (e) {
      if (neighborhoodSessionEpoch(ref) != epoch ||
          generation != _loadGeneration) {
        state = state.copyWith(isLoading: false);
        return;
      }
      state = state.copyWith(isLoading: false, failure: e);
    }
  }

  List<DraftRecoveryCandidate> _mergeDraftCandidates(
    List<DraftRecoveryCandidate> existing,
    List<FeedPost> pageItems,
  ) {
    final byId = {for (final c in existing) c.id: c};
    for (final post in pageItems) {
      if (post.status != 'draft') {
        continue;
      }
      byId.putIfAbsent(
        post.id,
        () => DraftRecoveryCandidate.fromFeedPost(post),
      );
    }
    final merged = byId.values.toList()..sort((a, b) => a.id.compareTo(b.id));
    return merged;
  }
}

final draftRecoveryControllerProvider = NotifierProvider.autoDispose<
  DraftRecoveryController,
  DraftRecoveryBrowseState
>(DraftRecoveryController.new);
