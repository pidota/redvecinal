import '../chat_api_exception.dart';
import '../chat_json.dart';
import 'chat_enums.dart';

class ChatRoomGroup {
  const ChatRoomGroup({
    required this.id,
    required this.name,
    required this.slug,
  });

  factory ChatRoomGroup.fromJson(Map<String, dynamic> json) {
    return ChatRoomGroup(
      id: parseRequiredInt(json['id']),
      name: parseRequiredString(json['name']),
      slug: parseRequiredString(json['slug']),
    );
  }

  final int id;
  final String name;
  final String slug;
}

class ChatRoom {
  const ChatRoom({
    required this.id,
    required this.municipalityId,
    required this.neighborhoodGroupId,
    required this.type,
    required this.status,
    required this.rawType,
    required this.rawStatus,
    this.group,
  });

  factory ChatRoom.fromJson(Map<String, dynamic> json) {
    final rawType = parseRequiredString(json['type']);
    final rawStatus = parseRequiredString(json['status']);
    ChatRoomGroup? group;
    final rawGroup = json['group'];
    if (rawGroup is Map<String, dynamic>) {
      group = ChatRoomGroup.fromJson(rawGroup);
    } else if (rawGroup != null) {
      throw const ChatApiException();
    }

    return ChatRoom(
      id: parseRequiredInt(json['id']),
      municipalityId: parseRequiredInt(json['municipality_id']),
      neighborhoodGroupId: parseRequiredInt(json['neighborhood_group_id']),
      type: ChatRoomType.fromApi(rawType),
      status: ChatRoomStatus.fromApi(rawStatus),
      rawType: rawType,
      rawStatus: rawStatus,
      group: group,
    );
  }

  final int id;
  final int municipalityId;
  final int neighborhoodGroupId;
  final ChatRoomType type;
  final ChatRoomStatus status;
  final String rawType;
  final String rawStatus;
  final ChatRoomGroup? group;
}
