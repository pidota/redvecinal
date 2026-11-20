import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/network/unauthorized_handler.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/chat/application/chat_send_coordinator.dart';
import 'package:red_vecinal/features/chat/data/chat_repository.dart';
import 'package:red_vecinal/features/chat/data/chat_uncertain_store.dart';
import 'package:red_vecinal/features/chat/data/models/chat_enums.dart';

import '../auth/auth_test_support.dart';
import 'chat_test_support.dart';

const _uuid = '550e8400-e29b-41d4-a716-446655440099';

ProviderContainer _container(FakeChatGateway gateway, {ChatUncertainStore? store}) {
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(testAppConfig),
      authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
      tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      chatRepositoryProvider.overrideWithValue(gateway),
      chatUncertainStoreProvider.overrideWithValue(
        store ?? InMemoryChatUncertainStore(),
      ),
      chatSendCoordinatorProvider.overrideWith(
        () => ChatSendCoordinator(uuidV4: () => _uuid),
      ),
    ],
  );
  container.read(unauthorizedHandlerProvider.notifier).state =
      () => container.read(authControllerProvider.notifier).onSessionInvalidated();
  return container;
}

void main() {
  test('envío confirmado reutiliza UUID y no duplica POST en doble tap', () async {
    final gateway = FakeChatGateway(sendDelay: const Duration(milliseconds: 40));
    final container = _container(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());

    final coordinator = container.read(chatSendCoordinatorProvider.notifier);
    final first = coordinator.submit(roomId: 1, rawBody: 'Hola');
    final second = coordinator.submit(roomId: 1, rawBody: 'Hola');
    final results = await Future.wait([first, second]);

    expect(gateway.sendCalls, 1);
    expect(results.first?.clientMessageId, _uuid);
    expect(results.first?.status, ChatOutgoingStatus.confirmed);
    expect(results[1]?.clientMessageId, _uuid);
  });

  test('timeout deja uncertain y no reintenta solo', () async {
    final gateway = FakeChatGateway(sendFailure: const ApiTimeoutFailure());
    final store = InMemoryChatUncertainStore();
    final container = _container(gateway, store: store);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());

    final result = await container
        .read(chatSendCoordinatorProvider.notifier)
        .submit(roomId: 1, rawBody: 'Hola');

    expect(result?.status, ChatOutgoingStatus.uncertain);
    expect(gateway.sendCalls, 1);
    expect(store.snapshot, hasLength(1));
    expect(store.snapshot.single.clientMessageId, _uuid);
    expect(store.snapshot.single.body, 'Hola');
  });

  test('replay explícito conserva UUID; 429 no confirma', () async {
    final gateway = FakeChatGateway(sendFailure: const ApiRateLimitedFailure());
    final container = _container(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    final coordinator = container.read(chatSendCoordinatorProvider.notifier);

    final first = await coordinator.submit(roomId: 1, rawBody: 'Hola');
    expect(first?.status, ChatOutgoingStatus.uncertain);
    expect(first?.failure, isA<ApiRateLimitedFailure>());

    final retried = await coordinator.retry(first!.key);
    expect(retried?.clientMessageId, _uuid);
    expect(retried?.status, ChatOutgoingStatus.uncertain);
    expect(gateway.sendCalls, 2);
    expect(gateway.sendPayloads.every((p) => p['client_message_id'] == _uuid), isTrue);
    expect(gateway.sendPayloads.every((p) => p['body'] == 'Hola'), isTrue);
  });

  test('validación local no hace POST', () async {
    final gateway = FakeChatGateway();
    final container = _container(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());

    final result = await container
        .read(chatSendCoordinatorProvider.notifier)
        .submit(roomId: 1, rawBody: '   ');

    expect(result?.status, ChatOutgoingStatus.failedBeforeDispatch);
    expect(gateway.sendCalls, 0);
  });

  test('rehidratación conserva uncertain sin POST automático', () async {
    final store = InMemoryChatUncertainStore(
      seed: [
        ChatUncertainRecord(
          userId: 1,
          roomId: 1,
          clientMessageId: _uuid,
          body: 'Pendiente',
          status: ChatOutgoingStatus.sending,
          updatedAt: DateTime.utc(2026, 11, 20),
        ),
      ],
    );
    final gateway = FakeChatGateway();
    final container = _container(gateway, store: store);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());

    await container.read(chatSendCoordinatorProvider.notifier).ensureHydrated();
    final restored = container
        .read(chatSendCoordinatorProvider)
        .forRoom(userId: 1, roomId: 1)
        .single;
    expect(restored.status, ChatOutgoingStatus.uncertain);
    expect(restored.body, 'Pendiente');
    expect(gateway.sendCalls, 0);
  });
}
