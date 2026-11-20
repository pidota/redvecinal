import '../data/models/chat_enums.dart';
import '../data/models/chat_message.dart';

/// Un mensaje cuenta para `unread_count`: visible y de otro usuario.
bool chatMessageCountsTowardUnread(ChatMessage message, int userId) {
  return message.status == ChatMessageStatus.visible &&
      message.senderId != userId;
}

/// Último ID al que se puede avanzar sin marcar pendientes no presentados.
///
/// No asume IDs consecutivos ni cursor 0. Si el historial no cubre el
/// intervalo (cursor, candidato], devuelve null.
int? computeSafeReadFrontier({
  required Iterable<ChatMessage> timeline,
  required Set<int> presentedIds,
  required int userId,
  required int roomId,
  required int? confirmedCursor,
  required bool hasOlder,
  int? trustedMaxId,
}) {
  final messages = timeline
      .where((item) => item.chatRoomId == roomId && item.id > 0)
      .toList()
    ..sort((a, b) => a.id.compareTo(b.id));
  if (messages.isEmpty) {
    return null;
  }

  final minId = messages.first.id;
  final maxTrusted = trustedMaxId ?? messages.last.id;
  if (maxTrusted < minId) {
    return null;
  }

  if (confirmedCursor == null && hasOlder) {
    return null;
  }
  if (confirmedCursor != null && hasOlder && confirmedCursor < minId) {
    return null;
  }

  final floor = confirmedCursor ?? 0;
  final countable = messages.where(
    (item) =>
        chatMessageCountsTowardUnread(item, userId) &&
        item.id > floor &&
        item.id <= maxTrusted,
  );

  final presentedCandidates = presentedIds.where((id) {
    if (id <= floor || id > maxTrusted) {
      return false;
    }
    return messages.any((item) => item.id == id);
  }).toList()
    ..sort();

  int? best;
  for (final candidate in presentedCandidates) {
    final pending = countable.where((item) => item.id <= candidate);
    if (pending.every((item) => presentedIds.contains(item.id))) {
      best = candidate;
    } else {
      break;
    }
  }

  if (best == null || (confirmedCursor != null && best <= confirmedCursor)) {
    return null;
  }
  return best;
}
