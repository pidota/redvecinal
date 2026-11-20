/// `chat_rooms.status` del backend.
enum ChatRoomStatus {
  active,
  locked,
  archived,
  unknown;

  static ChatRoomStatus fromApi(String raw) {
    switch (raw) {
      case 'active':
        return ChatRoomStatus.active;
      case 'locked':
        return ChatRoomStatus.locked;
      case 'archived':
        return ChatRoomStatus.archived;
      default:
        return ChatRoomStatus.unknown;
    }
  }

  bool get isWritable => this == ChatRoomStatus.active;
}

/// `chat_rooms.type` del backend.
enum ChatRoomType {
  groupMain,
  unknown;

  static ChatRoomType fromApi(String raw) {
    switch (raw) {
      case 'group_main':
        return ChatRoomType.groupMain;
      default:
        return ChatRoomType.unknown;
    }
  }
}

/// `chat_messages.status` del backend.
enum ChatMessageStatus {
  visible,
  hidden,
  deletedBySender,
  unknown;

  static ChatMessageStatus fromApi(String raw) {
    switch (raw) {
      case 'visible':
        return ChatMessageStatus.visible;
      case 'hidden':
        return ChatMessageStatus.hidden;
      case 'deleted_by_sender':
        return ChatMessageStatus.deletedBySender;
      default:
        return ChatMessageStatus.unknown;
    }
  }

  bool get isVisibleToNeighbors => this == ChatMessageStatus.visible;
}

/// Estado local de un envío (no viaja al API).
enum ChatOutgoingStatus {
  draft,
  sending,
  confirmed,
  uncertain,
  failedBeforeDispatch,
}
