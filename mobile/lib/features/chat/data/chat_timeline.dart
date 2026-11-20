import 'models/chat_message.dart';

/// Historial en memoria: un mensaje por id, orden ascendente, sin mezclar salas.
class ChatTimeline {
  const ChatTimeline({this.byId = const {}});

  final Map<int, ChatMessage> byId;

  List<ChatMessage> get messages {
    final list = byId.values.toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    return list;
  }

  bool get isEmpty => byId.isEmpty;

  int? get minId {
    if (byId.isEmpty) {
      return null;
    }
    return byId.keys.reduce((a, b) => a < b ? a : b);
  }

  int? get maxId {
    if (byId.isEmpty) {
      return null;
    }
    return byId.keys.reduce((a, b) => a > b ? a : b);
  }

  ChatTimeline merge(Iterable<ChatMessage> incoming, {required int roomId}) {
    if (incoming.isEmpty) {
      return this;
    }
    final next = Map<int, ChatMessage>.from(byId);
    for (final message in incoming) {
      if (message.chatRoomId != roomId) {
        continue;
      }
      final existing = next[message.id];
      if (existing == null || message.version >= existing.version) {
        next[message.id] = message;
      }
    }
    return ChatTimeline(byId: next);
  }

  ChatMessage? byClientMessageId(String clientMessageId) {
    for (final message in byId.values) {
      if (message.clientMessageId == clientMessageId) {
        return message;
      }
    }
    return null;
  }
}
