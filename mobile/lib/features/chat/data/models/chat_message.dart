import '../chat_api_exception.dart';
import '../chat_json.dart';
import 'chat_enums.dart';

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.chatRoomId,
    required this.senderId,
    required this.body,
    required this.status,
    required this.rawStatus,
    required this.version,
    this.clientMessageId,
    this.editedAt,
    this.deletedAt,
    this.createdAt,
  });

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final rawStatus = parseRequiredString(json['status']);
    return ChatMessage(
      id: parseRequiredInt(json['id']),
      chatRoomId: parseRequiredInt(json['chat_room_id']),
      senderId: parseRequiredInt(json['sender_id']),
      body: parseRequiredString(json['body']),
      status: ChatMessageStatus.fromApi(rawStatus),
      rawStatus: rawStatus,
      version: parseRequiredInt(json['version']),
      clientMessageId: parseOptionalString(json['client_message_id']),
      editedAt: parseOptionalDate(json['edited_at']),
      deletedAt: parseOptionalDate(json['deleted_at']),
      createdAt: parseOptionalDate(json['created_at']),
    );
  }

  final int id;
  final int chatRoomId;
  final int senderId;
  final String body;
  final ChatMessageStatus status;
  final String rawStatus;
  final int version;
  final String? clientMessageId;
  final DateTime? editedAt;
  final DateTime? deletedAt;
  final DateTime? createdAt;
}

class ChatMessagePage {
  const ChatMessagePage({
    required this.messages,
    required this.limit,
  });

  final List<ChatMessage> messages;
  final int limit;

  bool get mayHaveMore => messages.length >= limit;

  int? get minId => messages.isEmpty ? null : messages.first.id;

  int? get maxId => messages.isEmpty ? null : messages.last.id;
}

class ChatUnreadCount {
  const ChatUnreadCount({required this.unreadCount});

  factory ChatUnreadCount.fromJson(Map<String, dynamic> json) {
    return ChatUnreadCount(unreadCount: parseRequiredInt(json['unread_count']));
  }

  final int unreadCount;
}

class ChatReadResult {
  const ChatReadResult({
    this.lastReadMessageId,
    this.lastReadAt,
  });

  factory ChatReadResult.fromJson(Map<String, dynamic> json) {
    return ChatReadResult(
      lastReadMessageId: parseOptionalInt(json['last_read_message_id']),
      lastReadAt: parseOptionalDate(json['last_read_at']),
    );
  }

  final int? lastReadMessageId;
  final DateTime? lastReadAt;
}

class ChatSendResult {
  const ChatSendResult({required this.message});

  factory ChatSendResult.fromJson(Map<String, dynamic> json) {
    try {
      return ChatSendResult(message: ChatMessage.fromJson(json));
    } on ChatApiException {
      rethrow;
    } on Object {
      throw const ChatApiException();
    }
  }

  final ChatMessage message;
}
