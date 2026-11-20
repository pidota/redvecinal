import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/core/theme/rv_theme.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/chat/application/chat_send_coordinator.dart';
import 'package:red_vecinal/features/chat/data/chat_repository.dart';
import 'package:red_vecinal/features/chat/data/chat_uncertain_store.dart';
import 'package:red_vecinal/features/chat/data/models/chat_message.dart';
import 'package:red_vecinal/features/chat/data/models/chat_room.dart';
import 'package:red_vecinal/features/chat/presentation/chat_conversation_screen.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'chat_test_support.dart';

const _uuid = '550e8400-e29b-41d4-a716-446655440099';

Future<void> pumpSend(
  WidgetTester tester, {
  required FakeChatGateway gateway,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        authControllerProvider.overrideWith(AuthenticatedBootAuthController.new),
        chatRepositoryProvider.overrideWithValue(gateway),
        chatUncertainStoreProvider.overrideWithValue(InMemoryChatUncertainStore()),
        chatSendCoordinatorProvider.overrideWith(
          () => ChatSendCoordinator(uuidV4: () => _uuid),
        ),
      ],
      child: MaterialApp(
        theme: RvTheme.light(),
        home: const ChatConversationScreen(roomId: 1),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _send => find.byTooltip('Enviar mensaje');

void main() {
  testWidgets('campo vacío y solo espacios no envían', (tester) async {
    final gateway = FakeChatGateway(rooms: [ChatRoom.fromJson(sampleRoomJson())]);
    await pumpSend(tester, gateway: gateway);
    await tester.tap(_send);
    await tester.pump();
    expect(gateway.sendCalls, 0);
    await tester.enterText(find.byType(TextField), '   ');
    await tester.pump();
    await tester.tap(_send);
    await tester.pump();
    expect(gateway.sendCalls, 0);
  });

  testWidgets('contador cerca del límite 4000', (tester) async {
    final gateway = FakeChatGateway(rooms: [ChatRoom.fromJson(sampleRoomJson())]);
    await pumpSend(tester, gateway: gateway);
    await tester.enterText(find.byType(TextField), 'a' * 3600);
    await tester.pump();
    expect(find.text('3600 / 4000'), findsOneWidget);
  });

  testWidgets('envío confirmado aparece en el hilo', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
      sendResult: ChatSendResult(
        message: ChatMessage.fromJson(
          sampleMessageJson(id: 88, body: 'Hola sala', clientMessageId: _uuid),
        ),
      ),
    );
    await pumpSend(tester, gateway: gateway);
    await tester.enterText(find.byType(TextField), '  Hola sala  ');
    await tester.pump();
    await tester.tap(_send);
    await tester.pumpAndSettle();
    expect(gateway.sendCalls, 1);
    expect(gateway.sendPayloads.single['body'], 'Hola sala');
    expect(gateway.sendPayloads.single['client_message_id'], _uuid);
    expect(find.text('Hola sala'), findsOneWidget);
    expect(find.text('Enviando'), findsNothing);
  });

  testWidgets('doble tap no duplica POST', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
      sendDelay: const Duration(milliseconds: 80),
    );
    await pumpSend(tester, gateway: gateway);
    await tester.enterText(find.byType(TextField), 'Hola');
    await tester.pump();
    await tester.tap(_send);
    await tester.tap(_send);
    await tester.pump();
    expect(find.text('Enviando'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(gateway.sendCalls, 1);
  });

  testWidgets('uncertain permite retry con la misma UUID', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
      sendFailure: const ApiTimeoutFailure(),
    );
    await pumpSend(tester, gateway: gateway);
    await tester.enterText(find.byType(TextField), 'Pendiente');
    await tester.pump();
    await tester.tap(_send);
    await tester.pumpAndSettle();
    expect(find.text('No confirmado'), findsOneWidget);
    gateway.sendFailure = null;
    await tester.tap(find.text('Reintentar envío'));
    await tester.pumpAndSettle();
    expect(gateway.sendCalls, 2);
    expect(
      gateway.sendPayloads.every((item) => item['client_message_id'] == _uuid),
      isTrue,
    );
  });

  testWidgets('429 queda incierto', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
      sendFailure: const ApiRateLimitedFailure(),
    );
    await pumpSend(tester, gateway: gateway);
    await tester.enterText(find.byType(TextField), 'Hola');
    await tester.pump();
    await tester.tap(_send);
    await tester.pumpAndSettle();
    expect(find.text('No confirmado'), findsOneWidget);
    expect(gateway.sendCalls, 1);
  });

  testWidgets('422 no confirma', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
      sendFailure: const ApiValidationFailure(
        {
          'body': ['Sala no escribible.'],
        },
        'Sala no escribible.',
      ),
    );
    await pumpSend(tester, gateway: gateway);
    await tester.enterText(find.byType(TextField), 'Hola');
    await tester.pump();
    await tester.tap(_send);
    await tester.pumpAndSettle();
    expect(find.text('No se envió'), findsOneWidget);
    expect(find.text('Sala no escribible.'), findsOneWidget);
    expect(gateway.sendCalls, 1);
  });

  testWidgets('sala no escribible oculta el compositor', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson(status: 'locked'))],
      history: [ChatMessage.fromJson(sampleMessageJson(body: 'Histórico'))],
    );
    await pumpSend(tester, gateway: gateway);
    expect(find.text('Esta conversación está en modo lectura.'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Histórico'), findsOneWidget);
  });
}
