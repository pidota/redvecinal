import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import '../data/models/neighborhood_group.dart';
import '../data/neighborhood_repository.dart';
import 'neighborhood_session.dart';

class MyGroupsController extends AutoDisposeAsyncNotifier<List<NeighborhoodGroup>> {
  @override
  Future<List<NeighborhoodGroup>> build() {
    ref.watch(authControllerProvider);
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated) {
      return Future.value(const []);
    }
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return Future.value(const []);
    }
    return _loadGuarded(epoch);
  }

  Future<List<NeighborhoodGroup>> _loadGuarded(int epoch) async {
    final groups = await ref.read(neighborhoodRepositoryProvider).myGroups();
    if (neighborhoodSessionEpoch(ref) != epoch) {
      return const [];
    }
    return groups;
  }

  Future<void> refresh() async {
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      state = const AsyncValue.data([]);
      return;
    }

    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadGuarded(epoch));
  }
}

final myGroupsControllerProvider =
    AutoDisposeAsyncNotifierProvider<MyGroupsController, List<NeighborhoodGroup>>(MyGroupsController.new);
