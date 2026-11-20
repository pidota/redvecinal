import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/unauthorized_handler.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
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

void main() {
  test('respuesta tardía de unread no pisa una sesión nueva', () async {
    final gateway = FakeChatGateway(
      unread: const ChatUnreadCount(unreadCount: 9),
      unreadDelay: const Duration(milliseconds: 40),
    );
    final container = _container(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser(id: 1));
    container.listen(chatUnreadControllerProvider(1), (_, __) {});
    final pending = container.read(chatUnreadControllerProvider(1).future);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser(id: 2, email: 'otro@test.com'));
    gateway.unread = const ChatUnreadCount(unreadCount: 1);
    final next = await container.read(chatUnreadControllerProvider(1).future);
    await pending;
    expect(next.unreadCount, 1);
  });

  test('logout deja unread en cero', () async {
    final gateway = FakeChatGateway(unread: const ChatUnreadCount(unreadCount: 4));
    final container = _container(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    expect(
      (await container.read(chatUnreadControllerProvider(1).future)).unreadCount,
      4,
    );
    await container.read(authControllerProvider.notifier).logout(localOnly: true);
    expect(
      (await container.read(chatUnreadControllerProvider(1).future)).unreadCount,
      0,
    );
  });
}
