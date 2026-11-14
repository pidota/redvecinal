import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import '../data/models/paginated_feed_posts.dart';
import '../data/post_repository.dart';

class MyPostsController extends AutoDisposeAsyncNotifier<PaginatedFeedPosts> {
  static const _empty = PaginatedFeedPosts(
    items: [],
    currentPage: 1,
    lastPage: 1,
  );

  bool _loadMoreInFlight = false;
  int _listGeneration = 0;

  bool get isLoadingMore => _loadMoreInFlight;

  @override
  Future<PaginatedFeedPosts> build() {
    ref.watch(authControllerProvider);
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return Future.value(_empty);
    }
    return _loadPageGuarded(1, epoch);
  }

  Future<void> refresh() async {
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      state = const AsyncValue.data(_empty);
      return;
    }

    final generation = ++_listGeneration;
    final previous = state.valueOrNull;
    state =
        previous == null
            ? const AsyncValue.loading()
            : AsyncValue<PaginatedFeedPosts>.loading().copyWithPrevious(
              AsyncValue.data(previous),
            );
    try {
      final page = await _loadPageGuarded(1, epoch);
      if (neighborhoodSessionEpoch(ref) != epoch) {
        if (previous != null) {
          state = AsyncValue.data(previous);
        } else if (state.isLoading) {
          state = const AsyncValue.data(_empty);
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
          state = const AsyncValue.data(_empty);
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
      final page = await ref
          .read(postRepositoryProvider)
          .listMyPosts(page: nextPage);
      if (neighborhoodSessionEpoch(ref) != epoch ||
          generation != _listGeneration) {
        return;
      }
      state = AsyncValue.data(current.append(page));
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

  Future<PaginatedFeedPosts> _loadPageGuarded(int page, int epoch) async {
    final result = await ref
        .read(postRepositoryProvider)
        .listMyPosts(page: page);
    if (neighborhoodSessionEpoch(ref) != epoch) {
      return _empty;
    }
    return result;
  }
}

final myPostsControllerProvider =
    AutoDisposeAsyncNotifierProvider<MyPostsController, PaginatedFeedPosts>(
      MyPostsController.new,
    );
