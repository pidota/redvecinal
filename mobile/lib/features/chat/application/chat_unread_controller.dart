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
  });

  final int unreadCount;
  final ChatReadResult? lastRead;
  final bool accessRevoked;
}

class ChatUnreadController
    extends AutoDisposeFamilyAsyncNotifier<ChatUnreadState, int> {
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

  Future<void> markRead({int? lastReadMessageId}) async {
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return;
    }
    try {
      final result = await ref.read(chatRepositoryProvider).markRead(
            roomId: arg,
            lastReadMessageId: lastReadMessageId,
          );
      if (neighborhoodSessionEpoch(ref) != epoch) {
        return;
      }
      final unread = await ref.read(chatRepositoryProvider).unreadCount(arg);
      if (neighborhoodSessionEpoch(ref) != epoch) {
        return;
      }
      state = AsyncValue.data(
        ChatUnreadState(
          unreadCount: unread.unreadCount,
          lastRead: result,
        ),
      );
    } on ApiForbiddenFailure {
      revokeChatRoomAccess(ref, arg);
      state = const AsyncValue.data(ChatUnreadState(accessRevoked: true));
    } on ApiSessionExpiredFailure {
      state = const AsyncValue.data(ChatUnreadState());
    }
  }

  Future<ChatUnreadState> _load(int roomId, int epoch) async {
    try {
      final unread = await ref.read(chatRepositoryProvider).unreadCount(roomId);
      if (neighborhoodSessionEpoch(ref) != epoch) {
        return const ChatUnreadState();
      }
      return ChatUnreadState(unreadCount: unread.unreadCount);
    } on ApiForbiddenFailure {
      revokeChatRoomAccess(ref, roomId);
      return const ChatUnreadState(accessRevoked: true);
    } on ApiSessionExpiredFailure {
      return const ChatUnreadState();
    }
  }
}

final chatUnreadControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ChatUnreadController, ChatUnreadState, int>(
  ChatUnreadController.new,
);
