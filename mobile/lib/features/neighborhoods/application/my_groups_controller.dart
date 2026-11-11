import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import '../data/models/neighborhood_group.dart';
import '../data/neighborhood_repository.dart';

class MyGroupsController extends AutoDisposeAsyncNotifier<List<NeighborhoodGroup>> {
  @override
  Future<List<NeighborhoodGroup>> build() {
    ref.watch(authControllerProvider);
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated) {
      return Future.value(const []);
    }
    return ref.read(neighborhoodRepositoryProvider).myGroups();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(_load);
  }

  Future<List<NeighborhoodGroup>> _load() {
    return ref.read(neighborhoodRepositoryProvider).myGroups();
  }
}

final myGroupsControllerProvider =
    AutoDisposeAsyncNotifierProvider<MyGroupsController, List<NeighborhoodGroup>>(MyGroupsController.new);
