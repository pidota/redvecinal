import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import '../data/chat_repository.dart';
import '../data/models/chat_room.dart';

class ChatRoomsController extends AutoDisposeAsyncNotifier<List<ChatRoom>> {
  @override
  Future<List<ChatRoom>> build() {
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

  Future<List<ChatRoom>> _loadGuarded(int epoch) async {
    final rooms = await ref.read(chatRepositoryProvider).listRooms();
    if (neighborhoodSessionEpoch(ref) != epoch) {
      return const [];
    }
    return rooms;
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

final chatRoomsControllerProvider =
    AutoDisposeAsyncNotifierProvider<ChatRoomsController, List<ChatRoom>>(
  ChatRoomsController.new,
);
