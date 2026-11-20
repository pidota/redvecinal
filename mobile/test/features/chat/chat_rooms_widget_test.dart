import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/chat/data/models/chat_room.dart';
import 'package:red_vecinal/features/chat/presentation/chat_conversation_screen.dart';
import 'package:red_vecinal/features/chat/presentation/chat_screen.dart';

import '../../test_helpers.dart';
import 'chat_test_support.dart';

Future<void> openChatTab(
  WidgetTester tester, {
  FakeChatGateway? gateway,
}) async {
  await openMainShellAuthenticated(tester, chatGateway: gateway);
  await tester.tap(navBarIcon(Icons.forum_outlined));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('listado muestra loading y luego salas', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [
        ChatRoom.fromJson(sampleRoomJson()),
        ChatRoom.fromJson(sampleRoomJson(id: 2, groupId: 8, status: 'locked')),
      ],
      roomsDelay: const Duration(milliseconds: 40),
    );
    await openMainShellAuthenticated(tester, chatGateway: gateway);
    await tester.tap(navBarIcon(Icons.forum_outlined));
    await tester.pump();
    expect(find.text('Cargando salas'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('Junta Centro'), findsNWidgets(2));
    expect(find.textContaining('Sala 1'), findsOneWidget);
    expect(find.text('Disponible'), findsOneWidget);
    expect(find.text('Solo lectura'), findsOneWidget);
    expect(find.text('Último mensaje'), findsNothing);
  });

  testWidgets('lista vacía', (tester) async {
    await openChatTab(tester);
    expect(find.text('Sin salas'), findsOneWidget);
  });

  testWidgets('error de red permite reintentar', (tester) async {
    final gateway = FakeChatGateway(roomsFailure: const ApiNetworkFailure());
    await openChatTab(tester, gateway: gateway);
    expect(find.text('No pudimos cargar las salas'), findsOneWidget);
    gateway.roomsFailure = null;
    gateway.rooms = [ChatRoom.fromJson(sampleRoomJson())];
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(find.text('Junta Centro'), findsOneWidget);
  });

  testWidgets('error de sesión muestra estado de autenticación', (tester) async {
    final gateway = FakeChatGateway(
      roomsFailure: const ApiSessionExpiredFailure(),
    );
    await openChatTab(tester, gateway: gateway);
    expect(find.text('Sesión no válida'), findsOneWidget);
  });

  testWidgets('403 en listado muestra acceso no disponible', (tester) async {
    final gateway = FakeChatGateway(roomsFailure: const ApiForbiddenFailure());
    await openChatTab(tester, gateway: gateway);
    expect(find.text('Acceso no disponible'), findsOneWidget);
  });

  testWidgets('navega a la conversación', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson(id: 7))],
      history: sampleHistory(count: 3, roomId: 7),
    );
    await openChatTab(tester, gateway: gateway);
    await tester.tap(find.text('Junta Centro'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatConversationScreen), findsOneWidget);
    expect(
      tester.widget<ChatConversationScreen>(find.byType(ChatConversationScreen)).roomId,
      7,
    );
  });

  testWidgets('ruta inválida de sala', (tester) async {
    await openChatTab(tester);
    final context = tester.element(find.byType(ChatScreen));
    GoRouter.of(context).push('/chat/no-id');
    await tester.pumpAndSettle();
    expect(find.text('Ruta no válida'), findsOneWidget);
  });
}
