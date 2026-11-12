import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../data/membership_request_repository.dart';
import '../data/models/membership_request.dart';
import '../data/models/paginated_membership_requests.dart';
import 'neighborhood_session.dart';

class MyMembershipRequestsController
    extends AutoDisposeAsyncNotifier<PaginatedMembershipRequests> {
  static const _empty = PaginatedMembershipRequests(items: [], currentPage: 1, lastPage: 1);

  bool _loadMoreInFlight = false;
  int _listGeneration = 0;
  final Set<int> _cancelInFlight = {};

  bool get isLoadingMore => _loadMoreInFlight;

  bool isCancelling(int requestId) => _cancelInFlight.contains(requestId);

  @override
  Future<PaginatedMembershipRequests> build() {
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
    if (current == null || !current.hasMore || _loadMoreInFlight || state.isLoading) {
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
      final page = await ref.read(membershipRequestRepositoryProvider).myRequests(page: nextPage);
      if (neighborhoodSessionEpoch(ref) != epoch || generation != _listGeneration) {
        return;
      }
      state = AsyncValue.data(current.append(page));
    } catch (_) {
      if (neighborhoodSessionEpoch(ref) != epoch || generation != _listGeneration) {
        return;
      }
      state = AsyncValue.data(current);
    } finally {
      _loadMoreInFlight = false;
    }
  }

  Future<ApiFailure?> cancelRequest(MembershipRequest request) async {
    if (!request.isPending || _cancelInFlight.contains(request.id)) {
      return null;
    }

    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return null;
    }

    _cancelInFlight.add(request.id);
    try {
      await ref.read(membershipRequestRepositoryProvider).cancel(request.id);
      if (neighborhoodSessionEpoch(ref) != epoch) {
        return null;
      }

      final current = state.valueOrNull;
      if (current != null) {
        state = AsyncValue.data(
          PaginatedMembershipRequests(
            items: current.items
                .map(
                  (r) => r.id == request.id
                      ? r.copyWith(status: 'cancelled', cancelledAt: DateTime.now())
                      : r,
                )
                .toList(),
            currentPage: current.currentPage,
            lastPage: current.lastPage,
          ),
        );
      }
      return null;
    } on ApiFailure catch (e) {
      if (neighborhoodSessionEpoch(ref) != epoch) {
        return null;
      }
      if (e is ApiConflictFailure || e is ApiNotFoundFailure) {
        await refresh();
      }
      return e;
    } finally {
      _cancelInFlight.remove(request.id);
    }
  }

  Future<PaginatedMembershipRequests> _loadPageGuarded(int page, int epoch) async {
    final result = await ref.read(membershipRequestRepositoryProvider).myRequests(page: page);
    if (neighborhoodSessionEpoch(ref) != epoch) {
      return _empty;
    }
    return result;
  }
}

final myMembershipRequestsControllerProvider =
    AutoDisposeAsyncNotifierProvider<MyMembershipRequestsController, PaginatedMembershipRequests>(
  MyMembershipRequestsController.new,
);
