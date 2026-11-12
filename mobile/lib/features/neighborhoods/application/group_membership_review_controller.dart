import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../data/membership_request_repository.dart';
import '../data/models/membership_request.dart';
import '../data/models/paginated_membership_requests.dart';
import 'neighborhood_session.dart';
import 'reviewable_groups_controller.dart';

class GroupMembershipReviewController
    extends AutoDisposeFamilyAsyncNotifier<PaginatedMembershipRequests, int> {
  static const _empty = PaginatedMembershipRequests(items: [], currentPage: 1, lastPage: 1);

  bool _loadMoreInFlight = false;
  int _listGeneration = 0;
  final Set<int> _decisionInFlight = {};

  bool get isLoadingMore => _loadMoreInFlight;
  bool isDeciding(int requestId) => _decisionInFlight.contains(requestId);

  @override
  Future<PaginatedMembershipRequests> build(int groupId) {
    ref.watch(authControllerProvider);
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return Future.value(_empty);
    }
    return _loadPageGuarded(groupId, 1, epoch);
  }

  Future<void> refresh() async {
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      state = const AsyncValue.data(_empty);
      return;
    }

    final generation = ++_listGeneration;
    state = const AsyncValue.loading();
    final next = await AsyncValue.guard(() => _loadPageGuarded(arg, 1, epoch));
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
      final page = await ref.read(membershipRequestRepositoryProvider).groupRequests(
            groupId: arg,
            status: 'pending',
            page: nextPage,
          );
      if (neighborhoodSessionEpoch(ref) != epoch || generation != _listGeneration) {
        return;
      }
      state = AsyncValue.data(current.append(page));
    } catch (e) {
      if (neighborhoodSessionEpoch(ref) != epoch || generation != _listGeneration) {
        return;
      }
      if (e is ApiForbiddenFailure) {
        await _onAuthorizationRevoked();
        state = AsyncValue.error(e, StackTrace.current);
        return;
      }
      state = AsyncValue.data(current);
    } finally {
      _loadMoreInFlight = false;
    }
  }

  Future<ApiFailure?> approve(MembershipRequest request, {String? reviewNote}) async {
    return _decide(request, approve: true, reviewNote: reviewNote);
  }

  Future<ApiFailure?> reject(MembershipRequest request, {String? reviewNote}) async {
    return _decide(request, approve: false, reviewNote: reviewNote);
  }

  Future<ApiFailure?> _decide(
    MembershipRequest request, {
    required bool approve,
    String? reviewNote,
  }) async {
    if (!request.isPending || _decisionInFlight.contains(request.id)) {
      return null;
    }

    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return null;
    }

    _decisionInFlight.add(request.id);
    try {
      final repo = ref.read(membershipRequestRepositoryProvider);
      if (approve) {
        await repo.approve(request.id, reviewNote: reviewNote);
      } else {
        await repo.reject(request.id, reviewNote: reviewNote);
      }
      if (neighborhoodSessionEpoch(ref) != epoch) {
        return null;
      }
      await refresh();
      return null;
    } on ApiFailure catch (e) {
      if (neighborhoodSessionEpoch(ref) != epoch) {
        return null;
      }
      if (e is ApiForbiddenFailure) {
        await _onAuthorizationRevoked();
        state = AsyncValue.error(e, StackTrace.current);
        return e;
      }
      if (e is ApiTimeoutFailure) {
        return e;
      }
      if (e is ApiConflictFailure || e is ApiNotFoundFailure) {
        await refresh();
      }
      return e;
    } finally {
      _decisionInFlight.remove(request.id);
    }
  }

  Future<PaginatedMembershipRequests> _loadPageGuarded(int groupId, int page, int epoch) async {
    try {
      final result = await ref.read(membershipRequestRepositoryProvider).groupRequests(
            groupId: groupId,
            status: 'pending',
            page: page,
          );
      if (neighborhoodSessionEpoch(ref) != epoch) {
        return _empty;
      }
      return result;
    } on ApiForbiddenFailure {
      if (neighborhoodSessionEpoch(ref) != epoch) {
        return _empty;
      }
      await _onAuthorizationRevoked();
      rethrow;
    }
  }

  Future<void> _onAuthorizationRevoked() async {
    ref.invalidate(reviewableGroupsControllerProvider);
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return;
    }
    await ref.read(reviewableGroupsControllerProvider.notifier).refresh();
  }
}

final groupMembershipReviewControllerProvider =
    AsyncNotifierProvider.autoDispose.family<GroupMembershipReviewController, PaginatedMembershipRequests, int>(
  GroupMembershipReviewController.new,
);
