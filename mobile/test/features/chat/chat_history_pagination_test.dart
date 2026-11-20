import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/network/unauthorized_handler.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/chat/application/chat_room_history_controller.dart';
import 'package:red_vecinal/features/chat/data/chat_repository.dart';
import 'package:red_vecinal/features/chat/data/models/chat_message.dart';

import '../auth/auth_test_support.dart';
import 'chat_test_support.dart';

ProviderContainer historyContainer(FakeChatGateway gateway) {
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
  test('carga inicial es el extremo reciente ASC', () async {
    final gateway = FakeChatGateway(history: sampleHistory(count: 120));
    final container = historyContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    final sub = container.listen(chatRoomHistoryControllerProvider(1), (_, __) {});
    addTearDown(sub.close);

    final state = await container.read(chatRoomHistoryControllerProvider(1).future);
    expect(state.timeline.messages.map((m) => m.id), List<int>.generate(30, (i) => 91 + i));
    expect(state.caughtUpNewer, isTrue);
    expect(state.hasOlder, isTrue);
    expect(state.timeline.messages, isA<List<ChatMessage>>());
    expect(
      state.timeline.messages.map((m) => m.id).toList(),
      state.timeline.messages.map((m) => m.id).toList()..sort(),
    );
  });

  test('loadOlder añade la ventana previa sin duplicar', () async {
    final gateway = FakeChatGateway(history: sampleHistory(count: 120));
    final container = historyContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    final sub = container.listen(chatRoomHistoryControllerProvider(1), (_, __) {});
    addTearDown(sub.close);

    await container.read(chatRoomHistoryControllerProvider(1).future);
    await container.read(chatRoomHistoryControllerProvider(1).notifier).loadOlder();
    final state = container.read(chatRoomHistoryControllerProvider(1)).requireValue;
    expect(state.timeline.messages.map((m) => m.id), List<int>.generate(60, (i) => 61 + i));
    expect(state.timeline.messages.map((m) => m.id).toSet(), hasLength(60));
    expect(state.hasOlder, isTrue);
    expect(state.caughtUpNewer, isTrue);
    expect(state.isLoadingOlder, isFalse);
  });

  test('refreshNewer agrega posteriores y página vacía no borra', () async {
    final gateway = FakeChatGateway(history: sampleHistory(count: 120));
    final container = historyContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    final sub = container.listen(chatRoomHistoryControllerProvider(1), (_, __) {});
    addTearDown(sub.close);

    await container.read(chatRoomHistoryControllerProvider(1).future);
    await container.read(chatRoomHistoryControllerProvider(1).notifier).refreshNewer();
    expect(
      container.read(chatRoomHistoryControllerProvider(1)).requireValue.timeline.messages,
      hasLength(30),
    );

    gateway.history = sampleHistory(count: 125);
    await container.read(chatRoomHistoryControllerProvider(1).notifier).refreshNewer();
    final state = container.read(chatRoomHistoryControllerProvider(1)).requireValue;
    expect(state.timeline.messages.map((m) => m.id).last, 125);
    expect(state.timeline.messages, hasLength(35));
    expect(state.caughtUpNewer, isTrue);
  });

  test('carga incremental repetida cubre 120 mensajes', () async {
    final gateway = FakeChatGateway(history: sampleHistory(count: 120));
    final container = historyContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    final sub = container.listen(chatRoomHistoryControllerProvider(1), (_, __) {});
    addTearDown(sub.close);

    await container.read(chatRoomHistoryControllerProvider(1).future);
    final notifier = container.read(chatRoomHistoryControllerProvider(1).notifier);
    await notifier.loadOlder();
    await notifier.loadOlder();
    await notifier.loadOlder();
    await notifier.loadOlder();
    final state = container.read(chatRoomHistoryControllerProvider(1)).requireValue;
    expect(state.timeline.messages, hasLength(120));
    expect(state.timeline.messages.first.id, 1);
    expect(state.timeline.messages.last.id, 120);
    expect(state.hasOlder, isFalse);

    await notifier.loadOlder();
    final afterEmpty = container.read(chatRoomHistoryControllerProvider(1)).requireValue;
    expect(afterEmpty.timeline.messages, hasLength(120));
    expect(afterEmpty.hasOlder, isFalse);
  });

  test('ids no consecutivos y versión mayor ganan', () async {
    final gapped = [
      ...sampleHistory(count: 80),
      ...sampleHistory(count: 40, startId: 101),
    ];
    final gateway = FakeChatGateway(
      history: gapped,
      pages: {
        '1|140|null|30': ChatMessagePage(
          messages: [
            ChatMessage.fromJson(
              sampleMessageJson(id: 140, body: 'editado', version: 2),
            ),
          ],
          limit: 30,
        ),
      },
    );
    final container = historyContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    final sub = container.listen(chatRoomHistoryControllerProvider(1), (_, __) {});
    addTearDown(sub.close);

    final initial = await container.read(chatRoomHistoryControllerProvider(1).future);
    expect(initial.timeline.messages.first.id, 111);
    expect(initial.timeline.messages.last.id, 140);
    expect(initial.timeline.messages.any((m) => m.id == 80), isFalse);

    await container.read(chatRoomHistoryControllerProvider(1).notifier).refreshNewer();
    final updated = container.read(chatRoomHistoryControllerProvider(1)).requireValue;
    expect(updated.timeline.byId[140]?.version, 2);
    expect(updated.timeline.byId[140]?.body, 'editado');
  });

  test('cambio de sala no mezcla timelines', () async {
    final gateway = FakeChatGateway(
      history: [
        ...sampleHistory(count: 100, roomId: 1),
        ...sampleHistory(count: 100, roomId: 2, startId: 500),
      ],
    );
    final container = historyContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    final sub1 = container.listen(chatRoomHistoryControllerProvider(1), (_, __) {});
    final sub2 = container.listen(chatRoomHistoryControllerProvider(2), (_, __) {});
    addTearDown(sub1.close);
    addTearDown(sub2.close);

    final a = await container.read(chatRoomHistoryControllerProvider(1).future);
    final b = await container.read(chatRoomHistoryControllerProvider(2).future);
    expect(a.timeline.messages.every((m) => m.chatRoomId == 1), isTrue);
    expect(b.timeline.messages.every((m) => m.chatRoomId == 2), isTrue);
    expect(b.timeline.messages.last.id, 599);
  });

  test('logout y respuesta tardía no conservan historial', () async {
    final gateway = FakeChatGateway(
      history: sampleHistory(count: 100),
      listDelay: const Duration(milliseconds: 40),
    );
    final container = historyContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    final sub = container.listen(chatRoomHistoryControllerProvider(1), (_, __) {});
    addTearDown(sub.close);
    await Future<void>.delayed(const Duration(milliseconds: 1));
    await container.read(authControllerProvider.notifier).logout(localOnly: true);
    final state = await container.read(chatRoomHistoryControllerProvider(1).future);
    expect(state.timeline.isEmpty, isTrue);
  });

  test('401 deja el historial vacío', () async {
    final gateway = FakeChatGateway(
      history: sampleHistory(count: 100),
      listFailure: const ApiSessionExpiredFailure(),
    );
    final container = historyContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    final sub = container.listen(chatRoomHistoryControllerProvider(1), (_, __) {});
    addTearDown(sub.close);
    final state = await container.read(chatRoomHistoryControllerProvider(1).future);
    expect(state.timeline.isEmpty, isTrue);
    expect(state.accessRevoked, isFalse);
  });

  test('403 limpia la sala', () async {
    final gateway = FakeChatGateway(listFailure: const ApiForbiddenFailure());
    final container = historyContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    final sub = container.listen(chatRoomHistoryControllerProvider(4), (_, __) {});
    addTearDown(sub.close);
    final state = await container.read(chatRoomHistoryControllerProvider(4).future);
    expect(state.accessRevoked, isTrue);
    expect(state.timeline.isEmpty, isTrue);
  });
}
