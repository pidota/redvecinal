import '../data/models/chat_enums.dart';
import '../data/models/chat_room.dart';

String chatRoomTitle(ChatRoom room) {
  final name = room.group?.name.trim();
  if (name != null && name.isNotEmpty) {
    return name;
  }
  return 'Sala ${room.id}';
}

String chatRoomTypeLabel(ChatRoom room) {
  switch (room.type) {
    case ChatRoomType.groupMain:
      return 'Sala principal';
    case ChatRoomType.unknown:
      return room.rawType;
  }
}

String chatRoomStatusLabel(ChatRoom room) {
  switch (room.status) {
    case ChatRoomStatus.active:
      return 'Disponible';
    case ChatRoomStatus.locked:
      return 'Solo lectura';
    case ChatRoomStatus.archived:
      return 'Archivada';
    case ChatRoomStatus.unknown:
      return room.rawStatus;
  }
}

String formatChatTimestamp(DateTime? value) {
  if (value == null) {
    return '';
  }
  final local = value.toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final month = local.month.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$day/$month $hour:$minute';
}

String chatOutgoingStatusLabel(ChatOutgoingStatus status) {
  switch (status) {
    case ChatOutgoingStatus.sending:
      return 'Enviando';
    case ChatOutgoingStatus.confirmed:
      return 'Enviado';
    case ChatOutgoingStatus.uncertain:
      return 'No confirmado';
    case ChatOutgoingStatus.failedBeforeDispatch:
      return 'No se envió';
    case ChatOutgoingStatus.draft:
      return '';
  }
}
