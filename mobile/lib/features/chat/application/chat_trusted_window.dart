import '../data/models/chat_message.dart';

/// Amplía [currentTrustedMaxId] solo con el máximo de una página REST
/// obtenida desde [requestedAfterId].
///
/// No usa el máximo global del timeline. Una página vacía o un cursor
/// obsoleto no reducen ni saltan hasta mensajes ingeridos posteriores.
int? advanceTrustedMaxId({
  required int? currentTrustedMaxId,
  required int requestedAfterId,
  required Iterable<ChatMessage> pageMessages,
  required int roomId,
}) {
  var pageMax = 0;
  var hasPage = false;
  for (final message in pageMessages) {
    if (message.chatRoomId != roomId || message.id <= requestedAfterId) {
      continue;
    }
    hasPage = true;
    if (message.id > pageMax) {
      pageMax = message.id;
    }
  }
  if (!hasPage) {
    return currentTrustedMaxId;
  }
  if (currentTrustedMaxId != null && requestedAfterId != currentTrustedMaxId) {
    return currentTrustedMaxId;
  }
  if (currentTrustedMaxId != null && pageMax <= currentTrustedMaxId) {
    return currentTrustedMaxId;
  }
  return pageMax;
}
