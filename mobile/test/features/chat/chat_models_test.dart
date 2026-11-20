import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/chat/data/chat_api_exception.dart';
import 'package:red_vecinal/features/chat/data/models/chat_enums.dart';
import 'package:red_vecinal/features/chat/data/models/chat_message.dart';
import 'package:red_vecinal/features/chat/data/models/chat_room.dart';

import 'chat_test_support.dart';

void main() {
  group('ChatRoom.fromJson', () {
    test('parsing válido', () {
      final room = ChatRoom.fromJson(sampleRoomJson());
      expect(room.id, 1);
      expect(room.municipalityId, 10);
      expect(room.neighborhoodGroupId, 3);
      expect(room.type, ChatRoomType.groupMain);
      expect(room.status, ChatRoomStatus.active);
      expect(room.group?.name, 'Junta Centro');
    });

    test('estado y tipo desconocidos se conservan', () {
      final room = ChatRoom.fromJson(
        sampleRoomJson(status: 'mystery', type: 'dm'),
      );
      expect(room.status, ChatRoomStatus.unknown);
      expect(room.type, ChatRoomType.unknown);
      expect(room.rawStatus, 'mystery');
      expect(room.rawType, 'dm');
    });

    test('group opcional', () {
      final json = sampleRoomJson()..remove('group');
      final room = ChatRoom.fromJson(json);
      expect(room.group, isNull);
    });

    test('id ausente lanza ChatApiException', () {
      final json = sampleRoomJson()..remove('id');
      expect(() => ChatRoom.fromJson(json), throwsA(isA<ChatApiException>()));
    });
  });

  group('ChatMessage.fromJson', () {
    test('parsing válido con fechas ISO', () {
      final message = ChatMessage.fromJson(
        sampleMessageJson(
          editedAt: '2026-11-20T14:05:00.000000Z',
          deletedAt: null,
        ),
      );
      expect(message.id, 42);
      expect(message.body, 'Hola vecinos');
      expect(message.status, ChatMessageStatus.visible);
      expect(message.clientMessageId, '550e8400-e29b-41d4-a716-446655440000');
      expect(message.createdAt?.isUtc, isTrue);
      expect(message.editedAt, isNotNull);
      expect(message.deletedAt, isNull);
    });

    test('client_message_id nulo', () {
      final message = ChatMessage.fromJson(
        sampleMessageJson(clientMessageId: null),
      );
      expect(message.clientMessageId, isNull);
    });

    test('deleted_by_sender y hidden', () {
      expect(
        ChatMessage.fromJson(sampleMessageJson(status: 'hidden')).status,
        ChatMessageStatus.hidden,
      );
      expect(
        ChatMessage.fromJson(sampleMessageJson(status: 'deleted_by_sender')).status,
        ChatMessageStatus.deletedBySender,
      );
    });

    test('estado desconocido no se pierde', () {
      final message = ChatMessage.fromJson(sampleMessageJson(status: 'queued'));
      expect(message.status, ChatMessageStatus.unknown);
      expect(message.rawStatus, 'queued');
    });

    test('JSON incompleto', () {
      expect(
        () => ChatMessage.fromJson({'id': 1}),
        throwsA(isA<ChatApiException>()),
      );
    });

    test('fecha inválida', () {
      expect(
        () => ChatMessage.fromJson(sampleMessageJson(createdAt: 'no-es-fecha')),
        throwsA(isA<ChatApiException>()),
      );
    });
  });

  test('ChatUnreadCount y ChatReadResult', () {
    expect(
      ChatUnreadCount.fromJson({'unread_count': 4}).unreadCount,
      4,
    );
    final read = ChatReadResult.fromJson({
      'last_read_message_id': 9,
      'last_read_at': '2026-11-20T15:00:00.000000Z',
    });
    expect(read.lastReadMessageId, 9);
    expect(read.lastReadAt, isNotNull);
    expect(
      ChatReadResult.fromJson({
        'last_read_message_id': null,
        'last_read_at': null,
      }).lastReadMessageId,
      isNull,
    );
  });
}
