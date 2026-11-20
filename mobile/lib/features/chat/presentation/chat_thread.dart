import '../application/chat_outgoing.dart';
import '../data/chat_timeline.dart';
import '../data/models/chat_enums.dart';
import '../data/models/chat_message.dart';

class ChatThreadItem {
  const ChatThreadItem.server(this.message) : outgoing = null;

  const ChatThreadItem.outgoing(this.outgoing) : message = null;

  final ChatMessage? message;
  final ChatOutgoingMessage? outgoing;

  bool get isOutgoing => outgoing != null;
}

List<ChatThreadItem> buildChatThreadItems({
  required ChatTimeline timeline,
  required List<ChatOutgoingMessage> outgoing,
}) {
  final confirmedClientIds = <String>{};
  for (final item in outgoing) {
    final confirmed = item.confirmed;
    if (item.status == ChatOutgoingStatus.confirmed && confirmed != null) {
      final clientId = item.clientMessageId;
      if (clientId.isNotEmpty) {
        confirmedClientIds.add(clientId);
      }
    }
  }

  final items = <ChatThreadItem>[
    for (final message in timeline.messages) ChatThreadItem.server(message),
  ];

  final pending = outgoing.where((item) {
    if (item.status == ChatOutgoingStatus.confirmed) {
      return false;
    }
    if (item.status == ChatOutgoingStatus.draft) {
      return false;
    }
    final clientId = item.clientMessageId;
    if (clientId.isNotEmpty &&
        (confirmedClientIds.contains(clientId) ||
            timeline.byClientMessageId(clientId) != null)) {
      return false;
    }
    return true;
  }).toList()
    ..sort((a, b) => a.clientMessageId.compareTo(b.clientMessageId));

  for (final item in pending) {
    items.add(ChatThreadItem.outgoing(item));
  }

  return items;
}
