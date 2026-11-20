import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/network/unauthorized_handler.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/chat/application/chat_access.dart';
import 'package:red_vecinal/features/chat/application/chat_room_history_controller.dart';
import 'package:red_vecinal/features/chat/application/chat_rooms_controller.dart';
import 'package:red_vecinal/features/chat/application/chat_unread_controller.dart';
import 'package:red_vecinal/features/chat/data/chat_repository.dart';
import 'package:red_vecinal/features/chat/data/models/chat_message.dart';
import 'package:red_vecinal/features/chat/data/models/chat_room.dart';

import '../auth/auth_test_support.dart';
import 'chat_test_support.dart';

ProviderContainer sessionContainer(FakeChatGateway gateway) {
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(testAppConfig),
      authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
      tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      chatRepositoryProvider.overrideWithValue(gateway),
    ],
  );
  container.read(unauthorizedHandlerProvider.notifier).state =
      () => container.read(authControllerProvider.notifier).onSessionInvalidated();
  return container;
}

void main() {
  test('logout vacía salas', () async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
    );
    final container = sessionContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    final loaded = await container.read(chatRoomsControllerProvider.future);
    expect(loaded, hasLength(1));

    await container.read(authControllerProvider.notifier).logout(localOnly: true);
    final after = await container.read(chatRoomsControllerProvider.future);
    expect(after, isEmpty);
  });

  test('cambio de usuario no reutiliza salas anteriores', () async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson(id: 1))],
    );
    final container = sessionContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser(id: 1));
    expect((await container.read(chatRoomsControllerProvider.future)).single.id, 1);

    gateway.rooms = [ChatRoom.fromJson(sampleRoomJson(id: 8, municipalityId: 99))];
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser(id: 2, email: 'otro@test.com'));
    final next = await container.read(chatRoomsControllerProvider.future);
    expect(next.single.id, 8);
    expect(next.single.municipalityId, 99);
  });

  test('historial no mezcla salas', () async {
    final gateway = FakeChatGateway(
      pages: {
        '1': ChatMessagePage(
          messages: [ChatMessage.fromJson(sampleMessageJson(id: 1, roomId: 1))],
          limit: 30,
        ),
        '2': ChatMessagePage(
          messages: [ChatMessage.fromJson(sampleMessageJson(id: 9, roomId: 2))],
          limit: 30,
        ),
      },
    );
    final container = sessionContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());

    final room1 = await container.read(chatRoomHistoryControllerProvider(1).future);
    final room2 = await container.read(chatRoomHistoryControllerProvider(2).future);
    expect(room1.timeline.messages.single.chatRoomId, 1);
    expect(room2.timeline.messages.single.chatRoomId, 2);
  });

  test('403 revoca la sala y oculta historial', () async {
    final gateway = FakeChatGateway()
      ..pages = {
        '1': ChatMessagePage(
          messages: [ChatMessage.fromJson(sampleMessageJson())],
          limit: 30,
        ),
      };
    final container = sessionContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    await container.read(chatRoomHistoryControllerProvider(1).future);

    revokeChatRoomAccess(container, 1);
    container.invalidate(chatRoomHistoryControllerProvider(1));
    final revoked = await container.read(chatRoomHistoryControllerProvider(1).future);
    expect(revoked.accessRevoked, isTrue);
    expect(revoked.timeline.isEmpty, isTrue);
  });

  test('403 en carga inicial limpia el estado protegido', () async {
    final gateway = _ForbiddenOnListGateway();
    final container = sessionContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    final sub = container.listen(
      chatRoomHistoryControllerProvider(4),
      (_, __) {},
    );
    addTearDown(sub.close);
    final history = await container.read(chatRoomHistoryControllerProvider(4).future);
    expect(history.accessRevoked, isTrue);
    expect(history.timeline.isEmpty, isTrue);
    expect(container.read(chatRevokedRoomIdsProvider).contains(4), isTrue);
  });

  test('respuesta tardía de otra sesión no contamina historial', () async {
    final gateway = _DelayedListGateway();
    final container = sessionContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser(id: 1));
    final sub = container.listen(
      chatRoomHistoryControllerProvider(1),
      (_, __) {},
    );
    addTearDown(sub.close);
    await Future<void>.delayed(const Duration(milliseconds: 1));
    await container.read(authControllerProvider.notifier).logout(localOnly: true);
    final result =
        await container.read(chatRoomHistoryControllerProvider(1).future);
    expect(result.timeline.isEmpty, isTrue);
  });

  test('unread se vacía sin sesión', () async {
    final gateway = FakeChatGateway(
      unread: const ChatUnreadCount(unreadCount: 5),
    );
    final container = sessionContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    expect(
      (await container.read(chatUnreadControllerProvider(1).future)).unreadCount,
      5,
    );
    await container.read(authControllerProvider.notifier).logout(localOnly: true);
    expect(
      (await container.read(chatUnreadControllerProvider(1).future)).unreadCount,
      0,
    );
  });
}

class _ForbiddenOnListGateway extends FakeChatGateway {
  @override
  Future<ChatMessagePage> listMessages({
    required int roomId,
    int? afterId,
    int? beforeId,
    int limit = 30,
    CancelToken? cancelToken,
  }) async {
    throw const ApiForbiddenFailure();
  }
}

class _DelayedListGateway extends FakeChatGateway {
  @override
  Future<ChatMessagePage> listMessages({
    required int roomId,
    int? afterId,
    int? beforeId,
    int limit = 30,
    CancelToken? cancelToken,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    return ChatMessagePage(
      messages: [ChatMessage.fromJson(sampleMessageJson(roomId: roomId))],
      limit: 30,
    );
  }
}
