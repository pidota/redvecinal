import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/core/theme/rv_theme.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/chat/data/chat_repository.dart';
import 'package:red_vecinal/features/chat/data/chat_uncertain_store.dart';
import 'package:red_vecinal/features/chat/data/models/chat_message.dart';
import 'package:red_vecinal/features/chat/data/models/chat_room.dart';
import 'package:red_vecinal/features/chat/presentation/chat_conversation_screen.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'chat_test_support.dart';

Future<void> pumpConversation(
  WidgetTester tester, {
  required FakeChatGateway gateway,
  Size? size,
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
      ],
      child: MaterialApp(
        theme: RvTheme.light(),
        home: ChatConversationScreen(roomId: 1),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('historial reciente en orden cronológico propio/ajeno', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
      history: [
        ChatMessage.fromJson(sampleMessageJson(id: 1, senderId: 2, body: 'Hola junta')),
        ChatMessage.fromJson(sampleMessageJson(id: 2, senderId: 1, body: 'Hola vecinos')),
        ChatMessage.fromJson(sampleMessageJson(id: 3, senderId: 2, body: 'Bien')),
      ],
    );
    await pumpConversation(tester, gateway: gateway);
    expect(find.text('Hola junta'), findsOneWidget);
    expect(find.text('Hola vecinos'), findsOneWidget);
    expect(find.text('Bien'), findsOneWidget);
    expect(find.text('Vecino 2'), findsWidgets);
  });

  testWidgets('hidden y deleted respetan presentación', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
      history: [
        ChatMessage.fromJson(
          sampleMessageJson(id: 1, status: 'hidden', body: 'contenido-moderado'),
        ),
        ChatMessage.fromJson(
          sampleMessageJson(id: 2, senderId: 1, status: 'deleted_by_sender', body: 'secreto'),
        ),
      ],
    );
    await pumpConversation(tester, gateway: gateway);
    expect(find.text('contenido-moderado'), findsOneWidget);
    expect(find.text('Oculto'), findsOneWidget);
    expect(find.text('Este mensaje fue eliminado'), findsOneWidget);
    expect(find.text('secreto'), findsNothing);
  });

  testWidgets('sala sin mensajes', (tester) async {
    final gateway = FakeChatGateway(rooms: [ChatRoom.fromJson(sampleRoomJson())]);
    await pumpConversation(tester, gateway: gateway);
    expect(find.text('Sin mensajes'), findsOneWidget);
  });

  testWidgets('carga anterior añade ventana previa', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
      history: sampleHistory(count: 60),
    );
    await pumpConversation(tester, gateway: gateway);
    expect(find.text('msg-60'), findsOneWidget);
    final calls = gateway.listCalls;
    await tester.tap(find.text('Cargar mensajes anteriores'));
    await tester.pumpAndSettle();
    expect(gateway.listCalls, calls + 1);
  });

  testWidgets('320 px sin overflow', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
      history: sampleHistory(count: 40),
    );
    await pumpConversation(tester, gateway: gateway, size: const Size(320, 640));
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Sala 1'), findsOneWidget);
  });

  testWidgets('actualización manual pide after_id', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
      history: sampleHistory(count: 5),
    );
    await pumpConversation(tester, gateway: gateway);
    final before = gateway.listCalls;
    await tester.tap(find.byTooltip('Actualizar mensajes'));
    await tester.pumpAndSettle();
    expect(gateway.listCalls, greaterThan(before));
  });

  testWidgets('403 oculta historial', (tester) async {
    final gateway = FakeChatGateway(listFailure: const ApiForbiddenFailure());
    await pumpConversation(tester, gateway: gateway);
    expect(find.text('Acceso revocado'), findsOneWidget);
    expect(find.text('Hola vecinos'), findsNothing);
  });
}
