import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/chat/data/models/chat_message.dart';
import 'package:red_vecinal/features/chat/data/models/chat_room.dart';
import 'package:red_vecinal/features/chat/presentation/chat_labels.dart';
import 'package:red_vecinal/features/chat/presentation/widgets/chat_unread_badge.dart';

import 'chat_rooms_widget_test.dart';
import 'chat_test_support.dart';

void main() {
  test('cero no genera etiqueta compacta; 100 se compacta a 99+', () {
    expect(compactUnreadCountLabel(0), '');
    expect(compactUnreadCountLabel(4), '4');
    expect(compactUnreadCountLabel(99), '99');
    expect(compactUnreadCountLabel(100), '99+');
  });

  testWidgets('cero no muestra badge y positivo sí', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [
        ChatRoom.fromJson(sampleRoomJson(id: 1)),
        ChatRoom.fromJson(sampleRoomJson(id: 2, groupId: 8)),
      ],
      unreadByRoom: const {
        1: ChatUnreadCount(unreadCount: 0),
        2: ChatUnreadCount(unreadCount: 4),
      },
    );
    await openChatTab(tester, gateway: gateway);
    expect(find.byType(ChatUnreadBadge), findsWidgets);
    expect(find.text('4'), findsOneWidget);
    expect(find.text('0'), findsNothing);
    expect(find.byKey(const ValueKey('chat-unread-count-4')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-unread-count-0')), findsNothing);
  });

  testWidgets('conteo grande usa 99+ sin perder el valor interno', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
      unread: const ChatUnreadCount(unreadCount: 128),
    );
    await openChatTab(tester, gateway: gateway);
    expect(find.text('99+'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-unread-count-128')), findsOneWidget);
  });

  testWidgets('error de una sala no bloquea las demás', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [
        ChatRoom.fromJson(sampleRoomJson(id: 1)),
        ChatRoom.fromJson(sampleRoomJson(id: 2, groupId: 8)),
      ],
      unreadByRoom: const {
        2: ChatUnreadCount(unreadCount: 7),
      },
      unreadFailureByRoom: const {
        1: ApiNetworkFailure(),
      },
    );
    await openChatTab(tester, gateway: gateway);
    expect(find.text('Junta Centro'), findsNWidgets(2));
    expect(find.text('7'), findsOneWidget);
    expect(find.text('No pudimos cargar las salas'), findsNothing);
  });

  testWidgets('refresh vuelve a consultar contadores', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [ChatRoom.fromJson(sampleRoomJson())],
      unread: const ChatUnreadCount(unreadCount: 2),
    );
    await openChatTab(tester, gateway: gateway);
    final before = gateway.unreadCalls;
    await tester.fling(find.byType(ListView), const Offset(0, 400), 1200);
    await tester.pumpAndSettle();
    expect(gateway.unreadCalls, greaterThan(before));
  });

  testWidgets('403 de una sala no expone badge ni tumba el listado', (tester) async {
    final gateway = FakeChatGateway(
      rooms: [
        ChatRoom.fromJson(sampleRoomJson(id: 1)),
        ChatRoom.fromJson(sampleRoomJson(id: 2, groupId: 9)),
      ],
      unreadByRoom: const {
        2: ChatUnreadCount(unreadCount: 3),
      },
      unreadFailureByRoom: const {
        1: ApiForbiddenFailure(),
      },
    );
    await openChatTab(tester, gateway: gateway);
    expect(find.text('Junta Centro'), findsNWidgets(2));
    expect(find.text('3'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-unread-count-3')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-unread-count-1')), findsNothing);
  });
}
