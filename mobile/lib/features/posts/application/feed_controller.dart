import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import '../data/models/paginated_feed_posts.dart';
import '../data/post_repository.dart';

class FeedController extends AutoDisposeAsyncNotifier<PaginatedFeedPosts> {
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
    state = const AsyncValue.loading();
    final next = await AsyncValue.guard(() => _loadPageGuarded(1, epoch));
    if (generation != _listGeneration) {
      return;
    }
    state = next;
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
          .listPosts(page: nextPage);
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
    final result = await ref.read(postRepositoryProvider).listPosts(page: page);
    if (neighborhoodSessionEpoch(ref) != epoch) {
      return _empty;
    }
    return result;
  }
}

final feedControllerProvider =
    AutoDisposeAsyncNotifierProvider<FeedController, PaginatedFeedPosts>(
      FeedController.new,
    );
