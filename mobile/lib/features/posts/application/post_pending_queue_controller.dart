import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import '../data/models/paginated_feed_posts.dart';
import '../data/models/paginated_pending_queue.dart';
import '../data/models/post_moderation_review.dart';
import '../data/post_repository.dart';

class PostPendingQueueController
    extends AutoDisposeFamilyAsyncNotifier<PaginatedPendingQueue, int> {
  bool _loadMoreInFlight = false;
  int _listGeneration = 0;

  bool get isLoadingMore => _loadMoreInFlight;

  @override
  Future<PaginatedPendingQueue> build(int groupId) {
    ref.watch(authControllerProvider);
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return Future.value(PaginatedPendingQueue.empty);
    }
    return _loadPageGuarded(groupId, 1, epoch);
  }

  Future<void> refresh() async {
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      state = const AsyncValue.data(PaginatedPendingQueue.empty);
      return;
    }

    final generation = ++_listGeneration;
    final previous = state.valueOrNull;
    state =
        previous == null
            ? const AsyncValue.loading()
            : AsyncValue<PaginatedPendingQueue>.loading().copyWithPrevious(
              AsyncValue.data(previous),
            );
    try {
      final page = await _loadPageGuarded(arg, 1, epoch);
      if (neighborhoodSessionEpoch(ref) != epoch) {
        if (previous != null) {
          state = AsyncValue.data(previous);
        } else if (state.isLoading) {
          state = const AsyncValue.data(PaginatedPendingQueue.empty);
        }
        return;
      }
      if (generation != _listGeneration) {
        if (previous != null && state.isLoading) {
          state = AsyncValue.data(previous);
        }
        return;
      }
      state = AsyncValue.data(page);
    } catch (e, st) {
      if (generation != _listGeneration) {
        if (previous != null) {
          state = AsyncValue.data(previous);
        } else if (state.isLoading) {
          state = const AsyncValue.data(PaginatedPendingQueue.empty);
        }
        return;
      }
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null ||
        !current.hasMore ||
        _loadMoreInFlight ||
        state.isLoading) {
      return;
    }

    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return;
    }

    _loadMoreInFlight = true;
    final generation = _listGeneration;
    final nextPage = current.currentPage + 1;
    try {
      final raw = await ref
          .read(postRepositoryProvider)
          .listPendingPosts(groupId: arg, page: nextPage);
      if (neighborhoodSessionEpoch(ref) != epoch ||
          generation != _listGeneration) {
        return;
      }
      final mapped = _mapFeedPage(raw);
      state = AsyncValue.data(current.append(mapped));
    } catch (_) {
      if (neighborhoodSessionEpoch(ref) != epoch ||
          generation != _listGeneration) {
        return;
      }
      state = AsyncValue.data(current);
    } finally {
      _loadMoreInFlight = false;
    }
  }

  Future<PaginatedPendingQueue> _loadPageGuarded(
    int groupId,
    int page,
    int epoch,
  ) async {
    final raw = await ref
        .read(postRepositoryProvider)
        .listPendingPosts(groupId: groupId, page: page);
    if (neighborhoodSessionEpoch(ref) != epoch) {
      return PaginatedPendingQueue.empty;
    }
    return _mapFeedPage(raw);
  }

  PaginatedPendingQueue _mapFeedPage(PaginatedFeedPosts raw) {
    int skipped = 0;
    final reviewable = <PostModerationReview>[];
    for (final post in raw.items) {
      final review = PostModerationReview.fromFeedPost(post);
      if (review != null) {
        reviewable.add(review);
      } else {
        skipped++;
        _logOmittedPost(post.id);
      }
    }

    return PaginatedPendingQueue(
      reviewableItems: reviewable,
      skippedItemCount: skipped,
      currentPage: raw.currentPage,
      lastPage: raw.lastPage,
    );
  }
}

void _logOmittedPost(int postId) {
  assert(() {
    debugPrint(
      'PostPendingQueue: entrada omitida (sin pending_content) id=$postId',
    );
    return true;
  }());
}

final postPendingQueueControllerProvider =
    AutoDisposeAsyncNotifierProvider.family<
      PostPendingQueueController,
      PaginatedPendingQueue,
      int
    >(PostPendingQueueController.new);
