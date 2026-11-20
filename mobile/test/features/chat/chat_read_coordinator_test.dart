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
import 'package:red_vecinal/features/chat/application/chat_read_coordinator.dart';
import 'package:red_vecinal/features/chat/application/chat_room_history_controller.dart';
import 'package:red_vecinal/features/chat/application/chat_unread_controller.dart';
import 'package:red_vecinal/features/chat/data/chat_repository.dart';
import 'package:red_vecinal/features/chat/data/models/chat_message.dart';

import '../auth/auth_test_support.dart';
import 'chat_test_support.dart';

ProviderContainer _container(FakeChatGateway gateway) {
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

ChatReadSighting _sighting({
  required ChatMessage message,
  int roomId = 1,
  int userId = 1,
  bool appResumed = true,
  bool routeCurrent = true,
  ChatReadTrigger trigger = ChatReadTrigger.layout,
}) {
  return ChatReadSighting(
    roomId: roomId,
    userId: userId,
    message: message,
    appResumed: appResumed,
    routeCurrent: routeCurrent,
    trigger: trigger,
  );
}

Future<void> _prepareRoom(
  ProviderContainer container, {
  int roomId = 1,
  int userId = 1,
}) async {
  container.read(authControllerProvider.notifier).state =
      AuthAuthenticated(sampleAuthUser(id: userId));
  container.listen(chatRoomHistoryControllerProvider(roomId), (_, __) {});
  container.listen(chatReadCoordinatorProvider(roomId), (_, __) {});
  container.listen(chatUnreadControllerProvider(roomId), (_, __) {});
  await container.read(chatRoomHistoryControllerProvider(roomId).future);
}

Future<void> _presentAll(
  ChatReadCoordinator coordinator,
  List<ChatMessage> messages,
) async {
  for (final message in messages) {
    await coordinator.consider(_sighting(message: message));
  }
}

List<ChatMessage> _pendingOthers() {
  return List<ChatMessage>.generate(10, (index) {
    final id = 101 + index;
    return ChatMessage.fromJson(
      sampleMessageJson(id: id, senderId: 2, body: 'msg-$id'),
    );
  });
}

void main() {
  test('A: presentar solo 110 no envía POST ni reduce el contador', () async {
    final pending = _pendingOthers();
    final gateway = FakeChatGateway(
      history: pending,
      unread: const ChatUnreadCount(unreadCount: 10),
      zeroUnreadAfterRead: false,
    );
    final container = _container(gateway);
    addTearDown(container.dispose);
    await _prepareRoom(container);
    await container
        .read(chatReadCoordinatorProvider(1).notifier)
        .consider(_sighting(message: pending.last));
    expect(gateway.markReadCalls, 0);
    expect(
      (await container.read(chatUnreadControllerProvider(1).future)).unreadCount,
      10,
    );
  });

  test('B: frontera completa POST 110 y refresca unread', () async {
    final pending = _pendingOthers();
    final gateway = FakeChatGateway(
      history: pending,
      unread: const ChatUnreadCount(unreadCount: 10),
    );
    final container = _container(gateway);
    addTearDown(container.dispose);
    await _prepareRoom(container);
    await _presentAll(container.read(chatReadCoordinatorProvider(1).notifier), pending);
    expect(gateway.markReadPayloads.last['last_read_message_id'], 110);
    expect(container.read(chatReadCoordinatorProvider(1)).confirmedCursor, 110);
    expect(
      (await container.read(chatUnreadControllerProvider(1).future)).unreadCount,
      0,
    );
  });

  test('C: visibilidad parcial no marca 104-106 ni 109', () async {
    final pending = _pendingOthers();
    final gateway = FakeChatGateway(history: pending);
    final container = _container(gateway);
    addTearDown(container.dispose);
    await _prepareRoom(container);
    final coordinator = container.read(chatReadCoordinatorProvider(1).notifier);
    for (final id in [101, 102, 103, 107, 108, 110]) {
      await coordinator.consider(
        _sighting(message: pending.firstWhere((item) => item.id == id)),
      );
    }
    expect(gateway.markReadPayloads.last['last_read_message_id'], 103);
    expect(
      gateway.markReadPayloads.map((item) => item['last_read_message_id']),
      isNot(contains(110)),
    );
  });

  test('D: IDs no consecutivos acreditados avanzan a 115', () async {
    final gapped = [101, 104, 109, 115]
        .map((id) => ChatMessage.fromJson(sampleMessageJson(id: id, senderId: 2)))
        .toList();
    final gateway = FakeChatGateway(history: gapped);
    final container = _container(gateway);
    addTearDown(container.dispose);
    await _prepareRoom(container);
    await _presentAll(container.read(chatReadCoordinatorProvider(1).notifier), gapped);
    expect(gateway.markReadPayloads.last['last_read_message_id'], 115);
  });

  test('E: página reciente con hasOlder no avanza a 120', () async {
    final history = sampleHistory(count: 120, senderId: 2);
    final gateway = FakeChatGateway(history: history);
    final container = _container(gateway);
    addTearDown(container.dispose);
    await _prepareRoom(container);
    final loaded = container.read(chatRoomHistoryControllerProvider(1)).valueOrNull;
    expect(loaded?.hasOlder, isTrue);
    final coordinator = container.read(chatReadCoordinatorProvider(1).notifier);
    for (final message in history.where((item) => item.id >= 91)) {
      await coordinator.consider(_sighting(message: message));
    }
    expect(gateway.markReadCalls, 0);
  });

  test('F: propio intercalado no se exige para avanzar ajenos', () async {
    final mixed = [
      ChatMessage.fromJson(sampleMessageJson(id: 101, senderId: 2)),
      ChatMessage.fromJson(sampleMessageJson(id: 102, senderId: 1, body: 'propio')),
      ChatMessage.fromJson(sampleMessageJson(id: 103, senderId: 2)),
    ];
    final gateway = FakeChatGateway(history: mixed);
    final container = _container(gateway);
    addTearDown(container.dispose);
    await _prepareRoom(container);
    final coordinator = container.read(chatReadCoordinatorProvider(1).notifier);
    await coordinator.consider(_sighting(message: mixed.first));
    await coordinator.consider(_sighting(message: mixed.last));
    expect(gateway.markReadPayloads.last['last_read_message_id'], 103);
  });

  test('G: hidden/deleted no adelantan si falta un visible ajeno', () async {
    final timeline = [
      ChatMessage.fromJson(sampleMessageJson(id: 101, senderId: 2)),
      ChatMessage.fromJson(sampleMessageJson(id: 102, senderId: 2, status: 'hidden')),
      ChatMessage.fromJson(
        sampleMessageJson(id: 103, senderId: 1, status: 'deleted_by_sender'),
      ),
      ChatMessage.fromJson(sampleMessageJson(id: 104, senderId: 2)),
    ];
    final gateway = FakeChatGateway(history: timeline);
    final container = _container(gateway);
    addTearDown(container.dispose);
    await _prepareRoom(container);
    final coordinator = container.read(chatReadCoordinatorProvider(1).notifier);
    await coordinator.consider(_sighting(message: timeline.last));
    expect(gateway.markReadCalls, 0);
    await coordinator.consider(_sighting(message: timeline.first));
    expect(gateway.markReadPayloads.last['last_read_message_id'], 104);
  });

  test('no marca si la pantalla no está visible o la app está en background', () async {
    final messages = sampleHistory(count: 3, senderId: 2);
    final gateway = FakeChatGateway(history: messages);
    final container = _container(gateway);
    addTearDown(container.dispose);
    await _prepareRoom(container);
    final coordinator = container.read(chatReadCoordinatorProvider(1).notifier);
    await coordinator.consider(_sighting(message: messages.last, appResumed: false));
    await coordinator.consider(_sighting(message: messages.last, routeCurrent: false));
    expect(gateway.markReadCalls, 0);
  });

  test('un solo POST en vuelo por sala', () async {
    final messages = sampleHistory(count: 5, senderId: 2);
    final gateway = FakeChatGateway(
      history: messages,
      markReadDelay: const Duration(milliseconds: 40),
    );
    final container = _container(gateway);
    addTearDown(container.dispose);
    await _prepareRoom(container);
    final coordinator = container.read(chatReadCoordinatorProvider(1).notifier);
    await Future.wait([
      for (final message in messages) coordinator.consider(_sighting(message: message)),
    ]);
    expect(gateway.markReadMaxInFlight, 1);
    expect(gateway.markReadCalls, greaterThan(0));
    expect(gateway.markReadPayloads.last['last_read_message_id'], 5);
  });

  test('403 revoca y 422/timeout no confirman', () async {
    final messages = sampleHistory(count: 2, senderId: 2);
    final forbidden = FakeChatGateway(
      history: messages,
      markReadFailure: const ApiForbiddenFailure(),
    );
    final forbiddenContainer = _container(forbidden);
    addTearDown(forbiddenContainer.dispose);
    await _prepareRoom(forbiddenContainer);
    await _presentAll(
      forbiddenContainer.read(chatReadCoordinatorProvider(1).notifier),
      messages,
    );
    expect(forbiddenContainer.read(chatReadCoordinatorProvider(1)).confirmedCursor, isNull);
    expect(forbiddenContainer.read(chatReadCoordinatorProvider(1)).accessRevoked, isTrue);
    expect(forbiddenContainer.read(chatRevokedRoomIdsProvider).contains(1), isTrue);

    final invalid = FakeChatGateway(
      history: messages,
      markReadFailure: const ApiValidationFailure(
        {},
        'No se puede retroceder el marcador de lectura.',
      ),
    );
    final invalidContainer = _container(invalid);
    addTearDown(invalidContainer.dispose);
    await _prepareRoom(invalidContainer);
    await _presentAll(
      invalidContainer.read(chatReadCoordinatorProvider(1).notifier),
      messages,
    );
    expect(invalidContainer.read(chatReadCoordinatorProvider(1)).confirmedCursor, isNull);
    expect(
      invalidContainer.read(chatReadCoordinatorProvider(1)).lastFailure,
      isA<ApiValidationFailure>(),
    );

    final timeoutMessages = sampleHistory(count: 1, senderId: 2);
    final timeout = FakeChatGateway(
      history: timeoutMessages,
      markReadFailure: const ApiTimeoutFailure(),
    );
    final timeoutContainer = _container(timeout);
    addTearDown(timeoutContainer.dispose);
    await _prepareRoom(timeoutContainer);
    final timeoutCoordinator =
        timeoutContainer.read(chatReadCoordinatorProvider(1).notifier);
    await timeoutCoordinator.consider(_sighting(message: timeoutMessages.single));
    expect(timeoutContainer.read(chatReadCoordinatorProvider(1)).confirmedCursor, isNull);
    expect(timeout.markReadCalls, 1);
    await timeoutCoordinator.consider(_sighting(message: timeoutMessages.single));
    expect(timeout.markReadCalls, 1);
  });

  test('logout durante POST descarta la confirmación', () async {
    final messages = sampleHistory(count: 2, senderId: 2);
    final gateway = FakeChatGateway(
      history: messages,
      markReadDelay: const Duration(milliseconds: 40),
    );
    final container = _container(gateway);
    addTearDown(container.dispose);
    await _prepareRoom(container);
    final future = _presentAll(
      container.read(chatReadCoordinatorProvider(1).notifier),
      messages,
    );
    await container.read(authControllerProvider.notifier).logout(localOnly: true);
    await future;
    expect(container.read(chatReadCoordinatorProvider(1)).confirmedCursor, isNull);
  });

  test('sala no escribible pero legible marca con frontera completa', () async {
    final messages = sampleHistory(count: 3, senderId: 2);
    final gateway = FakeChatGateway(history: messages);
    final container = _container(gateway);
    addTearDown(container.dispose);
    await _prepareRoom(container);
    await _presentAll(container.read(chatReadCoordinatorProvider(1).notifier), messages);
    expect(gateway.markReadPayloads.last['last_read_message_id'], 3);
  });

  test('no envía IDs de otra sala ni inexistentes', () async {
    final messages = sampleHistory(count: 3, senderId: 2);
    final gateway = FakeChatGateway(history: messages);
    final container = _container(gateway);
    addTearDown(container.dispose);
    await _prepareRoom(container);
    final coordinator = container.read(chatReadCoordinatorProvider(1).notifier);
    await coordinator.consider(
      _sighting(
        message: ChatMessage.fromJson(sampleMessageJson(id: 2, roomId: 9)),
        roomId: 9,
      ),
    );
    await coordinator.consider(
      _sighting(message: ChatMessage.fromJson(sampleMessageJson(id: 99, roomId: 1))),
    );
    expect(gateway.markReadCalls, 0);
  });

  test('H: ingest 150 y página 111-140 no confirman read=150', () async {
    final loaded = [
      for (var id = 101; id <= 110; id++)
        ChatMessage.fromJson(sampleMessageJson(id: id, senderId: 2)),
    ];
    final newerPage = [
      for (var id = 111; id <= 140; id++)
        ChatMessage.fromJson(sampleMessageJson(id: id, senderId: 2)),
    ];
    final own = ChatMessage.fromJson(sampleMessageJson(id: 150, senderId: 1));
    final gateway = FakeChatGateway(
      pages: {
        '1': ChatMessagePage(messages: loaded, limit: 30),
        '1|110|null|30': ChatMessagePage(messages: newerPage, limit: 30),
      },
      unread: const ChatUnreadCount(unreadCount: 49),
      zeroUnreadAfterRead: false,
    );
    final container = _container(gateway);
    addTearDown(container.dispose);
    await _prepareRoom(container);
    final history = container.read(chatRoomHistoryControllerProvider(1).notifier);
    history.ingestConfirmed(own);
    await history.refreshNewer();
    expect(
      container.read(chatRoomHistoryControllerProvider(1)).requireValue.trustedMaxId,
      140,
    );
    final coordinator = container.read(chatReadCoordinatorProvider(1).notifier);
    await _presentAll(coordinator, [...loaded, ...newerPage, own]);
    expect(
      gateway.markReadPayloads.map((item) => item['last_read_message_id']),
      isNot(contains(150)),
    );
    expect(gateway.markReadPayloads.last['last_read_message_id'], 140);
    expect(container.read(chatReadCoordinatorProvider(1)).confirmedCursor, 140);
    expect(
      (await container.read(chatUnreadControllerProvider(1).future)).unreadCount,
      49,
    );
  });
}
