import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../data/models/neighborhood_group.dart';
import '../data/neighborhood_repository.dart';
import 'neighborhood_session.dart';

class GroupDetailController extends AutoDisposeFamilyAsyncNotifier<NeighborhoodGroup, int> {
  @override
  Future<NeighborhoodGroup> build(int groupId) {
    ref.watch(authControllerProvider);
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return Future.error(StateError('Sin sesión'));
    }
    return _loadDetail(groupId, epoch);
  }

  Future<void> refresh() async {
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      state = AsyncValue.error(StateError('Sin sesión'), StackTrace.current);
      return;
    }

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadDetail(arg, epoch));
  }

  Future<NeighborhoodGroup> _loadDetail(int groupId, int epoch) async {
    final group = await ref.read(neighborhoodRepositoryProvider).groupDetail(groupId);
    if (neighborhoodSessionEpoch(ref) != epoch) {
      throw StateError('Respuesta de sesión anterior');
    }
    return group;
  }
}

final groupDetailControllerProvider =
    AsyncNotifierProvider.autoDispose.family<GroupDetailController, NeighborhoodGroup, int>(
  GroupDetailController.new,
);
