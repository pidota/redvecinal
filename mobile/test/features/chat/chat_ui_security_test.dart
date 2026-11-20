import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/network/unauthorized_handler.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/core/theme/rv_theme.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/chat/application/chat_room_history_controller.dart';
import 'package:red_vecinal/features/chat/data/chat_repository.dart';
import 'package:red_vecinal/features/chat/data/chat_uncertain_store.dart';
import 'package:red_vecinal/features/chat/data/models/chat_message.dart';
import 'package:red_vecinal/features/chat/data/models/chat_room.dart';
import 'package:red_vecinal/features/chat/presentation/chat_conversation_screen.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'chat_test_support.dart';

void main() {
  testWidgets('logout durante carga no conserva historial', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
      history: sampleHistory(count: 40),
      listDelay: const Duration(milliseconds: 50),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(testAppConfig),
          authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
          tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
          authControllerProvider.overrideWith(AuthenticatedBootAuthController.new),
          chatRepositoryProvider.overrideWithValue(gateway),
          chatUncertainStoreProvider.overrideWithValue(InMemoryChatUncertainStore()),
        ],
        child: MaterialApp(
          theme: RvTheme.light(),
          home: const ChatConversationScreen(roomId: 1),
        ),
      ),
    );
    await tester.pump();
    final context = tester.element(find.byType(ChatConversationScreen));
    final container = ProviderScope.containerOf(context);
    await container.read(authControllerProvider.notifier).logout(localOnly: true);
    await tester.pumpAndSettle();
    expect(find.text('msg-40'), findsNothing);
  });

  testWidgets('401 deja el hilo vacío', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
      listFailure: const ApiSessionExpiredFailure(),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(testAppConfig),
          authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
          tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
          authControllerProvider.overrideWith(AuthenticatedBootAuthController.new),
          chatRepositoryProvider.overrideWithValue(gateway),
          chatUncertainStoreProvider.overrideWithValue(InMemoryChatUncertainStore()),
        ],
        child: MaterialApp(
          theme: RvTheme.light(),
          home: const ChatConversationScreen(roomId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sin mensajes'), findsOneWidget);
  });

  testWidgets('cambio de sala no mezcla hilos', (tester) async {
    final gateway = FakeChatGateway(
      history: [
        ...sampleHistory(count: 5, roomId: 1),
        ...sampleHistory(count: 5, roomId: 2, startId: 50),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        chatRepositoryProvider.overrideWithValue(gateway),
        chatUncertainStoreProvider.overrideWithValue(InMemoryChatUncertainStore()),
      ],
    );
    addTearDown(container.dispose);
    container.read(unauthorizedHandlerProvider.notifier).state =
        () => container.read(authControllerProvider.notifier).onSessionInvalidated();
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
  });

  testWidgets('ingesta confirmada no duplica por id', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
      history: [
        ChatMessage.fromJson(sampleMessageJson(id: 10, body: 'viejo')),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        chatRepositoryProvider.overrideWithValue(gateway),
        chatUncertainStoreProvider.overrideWithValue(InMemoryChatUncertainStore()),
      ],
    );
    addTearDown(container.dispose);
    container.read(unauthorizedHandlerProvider.notifier).state =
        () => container.read(authControllerProvider.notifier).onSessionInvalidated();
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    final sub = container.listen(chatRoomHistoryControllerProvider(1), (_, __) {});
    addTearDown(sub.close);
    await container.read(chatRoomHistoryControllerProvider(1).future);
    final message = ChatMessage.fromJson(sampleMessageJson(id: 10, body: 'editado', version: 2));
    container.read(chatRoomHistoryControllerProvider(1).notifier).ingestConfirmed(message);
    final state = container.read(chatRoomHistoryControllerProvider(1)).requireValue;
    expect(state.timeline.messages, hasLength(1));
    expect(state.timeline.byId[10]?.body, 'editado');
  });
}
