import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/core/theme/rv_theme.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/chat/application/chat_route_observer.dart';
import 'package:red_vecinal/features/chat/data/chat_repository.dart';
import 'package:red_vecinal/features/chat/data/chat_uncertain_store.dart';
import 'package:red_vecinal/features/chat/data/models/chat_message.dart';
import 'package:red_vecinal/features/chat/data/models/chat_room.dart';
import 'package:red_vecinal/features/chat/presentation/chat_conversation_screen.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'chat_rooms_widget_test.dart';
import 'chat_test_support.dart';

Future<void> pumpReadConversation(
  WidgetTester tester, {
  required FakeChatGateway gateway,
  Size? size,
  required RouteObserver<ModalRoute<void>> observer,
}) async {
  if (size != null) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        authControllerProvider.overrideWith(AuthenticatedBootAuthController.new),
        chatRepositoryProvider.overrideWithValue(gateway),
        chatUncertainStoreProvider.overrideWithValue(InMemoryChatUncertainStore()),
        chatRouteObserverProvider.overrideWithValue(observer),
      ],
      child: MaterialApp(
        theme: RvTheme.light(),
        navigatorObservers: [observer],
        home: const ChatConversationScreen(roomId: 1),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('abrir en el extremo reciente no marca 101-109 no presentados', (
    tester,
  ) async {
    final history = List<ChatMessage>.generate(10, (index) {
      final id = 101 + index;
      return ChatMessage.fromJson(
        sampleMessageJson(id: id, senderId: 2, body: 'msg-$id'),
      );
    });
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
      history: history,
      unread: const ChatUnreadCount(unreadCount: 10),
      zeroUnreadAfterRead: false,
    );
    final observer = RouteObserver<ModalRoute<void>>();
    await pumpReadConversation(
      tester,
      gateway: gateway,
      observer: observer,
      size: const Size(320, 280),
    );
    expect(gateway.markReadCalls, 0);
    expect(
      gateway.markReadPayloads.where((item) => item['last_read_message_id'] == 110),
      isEmpty,
    );
  });

  testWidgets('pantalla visible marca el mensaje presentado', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
      history: [
        ChatMessage.fromJson(sampleMessageJson(id: 11, senderId: 2, body: 'Hola junta')),
      ],
      unread: const ChatUnreadCount(unreadCount: 1),
    );
    final observer = RouteObserver<ModalRoute<void>>();
    await pumpReadConversation(tester, gateway: gateway, observer: observer);
    expect(gateway.markReadCalls, 1);
    expect(gateway.markReadPayloads.single['last_read_message_id'], 11);
    expect(gateway.markReadPayloads.single['roomId'], 1);
  });

  testWidgets('app en background no marca lectura', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
      history: [
        ChatMessage.fromJson(sampleMessageJson(id: 11, senderId: 2, body: 'Hola junta')),
      ],
    );
    final observer = RouteObserver<ModalRoute<void>>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(testAppConfig),
          authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
          tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
          authControllerProvider.overrideWith(AuthenticatedBootAuthController.new),
          chatRepositoryProvider.overrideWithValue(gateway),
          chatUncertainStoreProvider.overrideWithValue(InMemoryChatUncertainStore()),
          chatRouteObserverProvider.overrideWithValue(observer),
        ],
        child: MaterialApp(
          theme: RvTheme.light(),
          navigatorObservers: [observer],
          home: const ChatConversationScreen(roomId: 1),
        ),
      ),
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(gateway.markReadCalls, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('pantalla cubierta no envía otro POST', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
      history: [
        ChatMessage.fromJson(sampleMessageJson(id: 11, senderId: 2, body: 'Hola junta')),
      ],
    );
    final observer = RouteObserver<ModalRoute<void>>();
    await pumpReadConversation(tester, gateway: gateway, observer: observer);
    expect(gateway.markReadCalls, 1);

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('cubierta')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('cubierta'), findsOneWidget);
    expect(gateway.markReadCalls, 1);
  });

  testWidgets('timeout no confirma lectura ni badge local', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
      history: [
        ChatMessage.fromJson(sampleMessageJson(id: 11, senderId: 2, body: 'Hola junta')),
      ],
      unread: const ChatUnreadCount(unreadCount: 3),
      markReadFailure: const ApiTimeoutFailure(),
      zeroUnreadAfterRead: false,
    );
    final observer = RouteObserver<ModalRoute<void>>();
    await pumpReadConversation(tester, gateway: gateway, observer: observer);
    expect(gateway.markReadCalls, 1);
    expect(gateway.unread, const ChatUnreadCount(unreadCount: 3));
  });

  testWidgets('sala no escribible sigue marcando lectura', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson(status: 'locked'))],
      history: [
        ChatMessage.fromJson(sampleMessageJson(id: 21, senderId: 2, body: 'Aviso')),
      ],
    );
    final observer = RouteObserver<ModalRoute<void>>();
    await pumpReadConversation(tester, gateway: gateway, observer: observer);
    expect(find.text('Esta conversación está en modo lectura.'), findsOneWidget);
    expect(gateway.markReadCalls, 1);
    expect(gateway.markReadPayloads.single['last_read_message_id'], 21);
  });

  testWidgets('badge se actualiza tras lectura confirmada al volver al listado', (
    tester,
  ) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
      history: [
        ChatMessage.fromJson(sampleMessageJson(id: 11, senderId: 2, body: 'Hola junta')),
      ],
      unread: const ChatUnreadCount(unreadCount: 2),
    );
    await openChatTab(tester, gateway: gateway);
    expect(find.text('2'), findsOneWidget);
    await tester.tap(find.text('Junta Centro'));
    await tester.pumpAndSettle();
    expect(gateway.markReadCalls, greaterThan(0));
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsNothing);
  });
}
