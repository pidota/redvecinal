import 'package:dio/dio.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/chat/data/chat_repository.dart';
import 'package:red_vecinal/features/chat/data/models/chat_message.dart';
import 'package:red_vecinal/features/chat/data/models/chat_room.dart';

List<ChatMessage> sampleHistory({
  required int count,
  int roomId = 1,
  int senderId = 1,
  int startId = 1,
}) {
  return List<ChatMessage>.generate(count, (index) {
    final id = startId + index;
    return ChatMessage.fromJson(
      sampleMessageJson(
        id: id,
        roomId: roomId,
        senderId: senderId,
        body: 'msg-$id',
        clientMessageId: null,
      ),
    );
  });
}

ChatMessagePage paginateChatMessages({
  required List<ChatMessage> messages,
  required int roomId,
  int? afterId,
  int? beforeId,
  int limit = 30,
}) {
  final visible = messages.where((item) => item.chatRoomId == roomId).toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  List<ChatMessage> slice;
  if (afterId != null) {
    slice = visible.where((item) => item.id > afterId).take(limit).toList();
  } else if (beforeId != null) {
    final older = visible.where((item) => item.id < beforeId).toList();
    slice = older.length <= limit
        ? older
        : older.sublist(older.length - limit);
  } else {
    slice = visible.length <= limit
        ? visible
        : visible.sublist(visible.length - limit);
  }
  return ChatMessagePage(messages: slice, limit: limit);
}

Map<String, dynamic> sampleRoomJson({
  int id = 1,
  int municipalityId = 10,
  int groupId = 3,
  String status = 'active',
  String type = 'group_main',
}) {
  return {
    'id': id,
    'municipality_id': municipalityId,
    'neighborhood_group_id': groupId,
    'type': type,
    'status': status,
    'group': {
      'id': groupId,
      'name': 'Junta Centro',
      'slug': 'junta-centro',
    },
  };
}

Map<String, dynamic> sampleMessageJson({
  int id = 42,
  int roomId = 1,
  int senderId = 1,
  String body = 'Hola vecinos',
  String status = 'visible',
  int version = 1,
  String? clientMessageId = '550e8400-e29b-41d4-a716-446655440000',
  String? createdAt = '2026-11-20T14:00:00.000000Z',
  String? editedAt,
  String? deletedAt,
}) {
  return {
    'id': id,
    'chat_room_id': roomId,
    'sender_id': senderId,
    'body': body,
    'status': status,
    'version': version,
    'client_message_id': clientMessageId,
    'edited_at': editedAt,
    'deleted_at': deletedAt,
    'created_at': createdAt,
  };
}

class FakeChatGateway implements ChatGateway {
  FakeChatGateway({
    this.rooms = const [],
    this.pages = const {},
    this.sendResult,
    this.sendFailure,
    this.unread = const ChatUnreadCount(unreadCount: 0),
    this.readResult = const ChatReadResult(),
    this.messageById = const {},
    this.sendDelay = Duration.zero,
    this.history = const [],
    this.listDelay = Duration.zero,
    this.listFailure,
    this.roomsFailure,
    this.roomsDelay = Duration.zero,
  });

  List<ChatRoom> rooms;
  Map<String, ChatMessagePage> pages;
  ChatSendResult? sendResult;
  Object? sendFailure;
  ChatUnreadCount unread;
  ChatReadResult readResult;
  Map<int, ChatMessage> messageById;
  int sendCalls = 0;
  final List<Map<String, dynamic>> sendPayloads = [];
  Duration sendDelay = Duration.zero;
  List<ChatMessage> history = const [];
  Duration listDelay = Duration.zero;
  Object? listFailure;
  Object? roomsFailure;
  Duration roomsDelay = Duration.zero;
  int listCalls = 0;

  @override
  Future<List<ChatRoom>> listRooms({CancelToken? cancelToken}) async {
    if (roomsDelay > Duration.zero) {
      await Future<void>.delayed(roomsDelay);
    }
    if (roomsFailure != null) {
      throw roomsFailure!;
    }
    return rooms;
  }

  @override
  Future<ChatMessagePage> listMessages({
    required int roomId,
    int? afterId,
    int? beforeId,
    int limit = 30,
    CancelToken? cancelToken,
  }) async {
    listCalls++;
    if (listDelay > Duration.zero) {
      await Future<void>.delayed(listDelay);
    }
    if (listFailure != null) {
      throw listFailure!;
    }
    final key = '$roomId|$afterId|$beforeId|$limit';
    if (pages.containsKey(key)) {
      return pages[key]!;
    }
    if (pages.containsKey('$roomId') && afterId == null && beforeId == null) {
      return pages['$roomId']!;
    }
    return paginateChatMessages(
      messages: history,
      roomId: roomId,
      afterId: afterId,
      beforeId: beforeId,
      limit: limit,
    );
  }

  @override
  Future<ChatSendResult> sendMessage({
    required int roomId,
    required String body,
    required String clientMessageId,
    CancelToken? cancelToken,
  }) async {
    sendCalls++;
    sendPayloads.add({
      'roomId': roomId,
      'body': body,
      'client_message_id': clientMessageId,
    });
    if (sendDelay > Duration.zero) {
      await Future<void>.delayed(sendDelay);
    }
    if (sendFailure != null) {
      throw sendFailure!;
    }
    return sendResult ??
        ChatSendResult(
          message: ChatMessage.fromJson(
            sampleMessageJson(
              roomId: roomId,
              body: body,
              clientMessageId: clientMessageId,
            ),
          ),
        );
  }

  @override
  Future<ChatMessage> getMessage(int messageId, {CancelToken? cancelToken}) async {
    final message = messageById[messageId];
    if (message == null) {
      throw const ApiNotFoundFailure();
    }
    return message;
  }

  @override
  Future<ChatReadResult> markRead({
    required int roomId,
    int? lastReadMessageId,
    CancelToken? cancelToken,
  }) async {
    return readResult;
  }

  @override
  Future<ChatUnreadCount> unreadCount(int roomId, {CancelToken? cancelToken}) async {
    return unread;
  }

  @override
  Future<ChatMessage> editMessage({
    required int messageId,
    required String body,
    CancelToken? cancelToken,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<ChatMessage> deleteMessage(int messageId, {CancelToken? cancelToken}) async {
    throw UnimplementedError();
  }

  @override
  Future<ChatMessage> hideMessage({
    required int messageId,
    String? reason,
    CancelToken? cancelToken,
  }) async {
    throw UnimplementedError();
  }

  @override
  Future<int> reportMessage({
    required int messageId,
    required String reasonCode,
    String? details,
    CancelToken? cancelToken,
  }) async {
    throw UnimplementedError();
  }
}
