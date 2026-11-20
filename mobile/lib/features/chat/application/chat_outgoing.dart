import '../../../core/network/api_failure.dart';
import '../data/chat_api_exception.dart';
import '../data/models/chat_enums.dart';
import '../data/models/chat_message.dart';

class ChatOutgoingMessage {
  const ChatOutgoingMessage({
    required this.userId,
    required this.roomId,
    required this.body,
    required this.clientMessageId,
    required this.status,
    this.confirmed,
    this.failure,
  });

  final int userId;
  final int roomId;
  final String body;
  final String clientMessageId;
  final ChatOutgoingStatus status;
  final ChatMessage? confirmed;
  final ApiFailure? failure;

  String get key => '$userId|$roomId|$clientMessageId';

  ChatOutgoingMessage copyWith({
    ChatOutgoingStatus? status,
    ChatMessage? confirmed,
    ApiFailure? failure,
    bool clearFailure = false,
  }) {
    return ChatOutgoingMessage(
      userId: userId,
      roomId: roomId,
      body: body,
      clientMessageId: clientMessageId,
      status: status ?? this.status,
      confirmed: confirmed ?? this.confirmed,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }
}

class ChatSendState {
  const ChatSendState({
    this.messages = const {},
    this.hydrated = false,
  });

  final Map<String, ChatOutgoingMessage> messages;
  final bool hydrated;

  List<ChatOutgoingMessage> forRoom({required int userId, required int roomId}) {
    return messages.values
        .where((item) => item.userId == userId && item.roomId == roomId)
        .toList();
  }
}

bool isChatSendUncertain(Object failure) {
  return failure is ApiTimeoutFailure ||
      failure is ApiNetworkFailure ||
      failure is ApiServerFailure ||
      failure is ApiRateLimitedFailure ||
      failure is ChatRequestCancelled ||
      failure is ChatApiException;
}

bool isChatSendRetryable(ChatOutgoingMessage message) {
  if (message.status == ChatOutgoingStatus.uncertain) {
    return true;
  }
  return message.status != ChatOutgoingStatus.confirmed &&
      message.status != ChatOutgoingStatus.sending &&
      message.failure is ApiRateLimitedFailure;
}
