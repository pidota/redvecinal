import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../data/membership_request_repository.dart';
import '../data/models/membership_request.dart';
import '../data/models/neighborhood_group.dart';
import 'my_membership_requests_controller.dart';
import 'neighborhood_session.dart';

class GroupJoinViewData {
  const GroupJoinViewData({
    required this.group,
    this.existingRequest,
  });

  final NeighborhoodGroup group;
  final MembershipRequest? existingRequest;
}

class GroupJoinController extends AutoDisposeFamilyAsyncNotifier<GroupJoinViewData, int> {
  bool _submitInFlight = false;

  bool get isSubmitting => _submitInFlight;

  @override
  Future<GroupJoinViewData> build(int groupId) {
    ref.watch(authControllerProvider);
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return Future.error(StateError('Sin sesión'));
    }
    return _load(groupId, epoch);
  }

  Future<void> refresh() async {
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      state = AsyncValue.error(StateError('Sin sesión'), StackTrace.current);
      return;
    }

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _load(arg, epoch));
  }

  Future<ApiFailure?> submit({String? requestNote}) async {
    if (_submitInFlight) {
      return null;
    }

    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return null;
    }

    final current = state.valueOrNull;
    if (current?.existingRequest?.isPending == true) {
      return const ApiConflictFailure('Ya tienes una solicitud pendiente para esta junta.');
    }

    _submitInFlight = true;
    try {
      final created = await ref.read(membershipRequestRepositoryProvider).submit(
            groupId: arg,
            requestNote: requestNote,
          );
      if (neighborhoodSessionEpoch(ref) != epoch) {
        return null;
      }

      final group = created.neighborhoodGroup ?? current?.group;
      if (group == null) {
        await refresh();
        return null;
      }
      state = AsyncValue.data(GroupJoinViewData(group: group, existingRequest: created));
      ref.invalidate(myMembershipRequestsControllerProvider);
      return null;
    } on ApiFailure catch (e) {
      if (neighborhoodSessionEpoch(ref) != epoch) {
        return null;
      }
      if (e is ApiConflictFailure) {
        await refresh();
      }
      return e;
    } finally {
      _submitInFlight = false;
    }
  }

  Future<GroupJoinViewData> _load(int groupId, int epoch) async {
    final repo = ref.read(membershipRequestRepositoryProvider);
    final group = await repo.membershipContext(groupId);
    if (neighborhoodSessionEpoch(ref) != epoch) {
      throw StateError('Respuesta de sesión anterior');
    }

    final existing = await _findExistingRequestForGroup(groupId, epoch);

    return GroupJoinViewData(group: group, existingRequest: existing);
  }

  /// Busca la solicitud más reciente del usuario para [groupId] recorriendo
  /// el listado paginado real (`GET /me/membership-requests`) sin filtros.
  Future<MembershipRequest?> _findExistingRequestForGroup(int groupId, int epoch) async {
    final repo = ref.read(membershipRequestRepositoryProvider);
    var page = 1;

    while (true) {
      final batch = await repo.myRequests(page: page);
      if (neighborhoodSessionEpoch(ref) != epoch) {
        throw StateError('Respuesta de sesión anterior');
      }

      for (final request in batch.items) {
        if (request.neighborhoodGroupId == groupId) {
          return request;
        }
      }

      if (!batch.hasMore) {
        return null;
      }
      page++;
    }
  }
}

final groupJoinControllerProvider =
    AsyncNotifierProvider.autoDispose.family<GroupJoinController, GroupJoinViewData, int>(
  GroupJoinController.new,
);
