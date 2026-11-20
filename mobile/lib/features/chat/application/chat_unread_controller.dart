import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import '../data/chat_repository.dart';
import '../data/models/chat_message.dart';
import 'chat_access.dart';

class ChatUnreadState {
  const ChatUnreadState({
    this.unreadCount = 0,
    this.lastRead,
    this.accessRevoked = false,
    this.loadFailed = false,
  });

  final int unreadCount;
  final ChatReadResult? lastRead;
  final bool accessRevoked;
  final bool loadFailed;
}

class ChatUnreadController
    extends AutoDisposeFamilyAsyncNotifier<ChatUnreadState, int> {
  int _generation = 0;

  @override
  Future<ChatUnreadState> build(int roomId) {
    ref.watch(authControllerProvider);
    ref.watch(chatRevokedRoomIdsProvider);
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return Future.value(const ChatUnreadState());
    }
    if (ref.read(chatRevokedRoomIdsProvider).contains(roomId)) {
      return Future.value(const ChatUnreadState(accessRevoked: true));
    }
    return _load(roomId, epoch);
  }

  Future<void> refresh() async {
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      state = const AsyncValue.data(ChatUnreadState());
      return;
    }
    if (ref.read(chatRevokedRoomIdsProvider).contains(arg)) {
      state = const AsyncValue.data(ChatUnreadState(accessRevoked: true));
      return;
    }
    state = await AsyncValue.guard(() => _load(arg, epoch));
    final current = state.valueOrNull;
    if (current != null && current.unreadCount < 0) {
      state = AsyncValue.data(
        ChatUnreadState(
          lastRead: current.lastRead,
          accessRevoked: current.accessRevoked,
          loadFailed: current.loadFailed,
        ),
      );
    }
  }

  Future<ChatUnreadState> _load(int roomId, int epoch) async {
    final generation = ++_generation;
    try {
      final unread = await ref.read(chatRepositoryProvider).unreadCount(roomId);
      if (!_stillCurrent(epoch, generation)) {
        return state.valueOrNull ?? const ChatUnreadState();
      }
      return ChatUnreadState(
        unreadCount: unread.unreadCount < 0 ? 0 : unread.unreadCount,
      );
    } on ApiForbiddenFailure {
      if (!_stillCurrent(epoch, generation)) {
        return state.valueOrNull ?? const ChatUnreadState();
      }
      revokeChatRoomAccess(ref, roomId);
      return const ChatUnreadState(accessRevoked: true);
    } on ApiSessionExpiredFailure {
      if (!_stillCurrent(epoch, generation)) {
        return state.valueOrNull ?? const ChatUnreadState();
      }
      return const ChatUnreadState();
    } on ApiFailure {
      if (!_stillCurrent(epoch, generation)) {
        return state.valueOrNull ?? const ChatUnreadState();
      }
      return ChatUnreadState(
        unreadCount: state.valueOrNull?.unreadCount ?? 0,
        lastRead: state.valueOrNull?.lastRead,
        loadFailed: true,
      );
    }
  }

  bool _stillCurrent(int epoch, int generation) {
    return neighborhoodSessionEpoch(ref) == epoch && generation == _generation;
  }
}

final chatUnreadControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ChatUnreadController, ChatUnreadState, int>(
  ChatUnreadController.new,
);
