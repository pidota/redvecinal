import 'package:flutter/foundation.dart';

/// Parámetros de familia para la revisión de moderación (junta + publicación).
@immutable
class PostModerationReviewKey {
  const PostModerationReviewKey({required this.groupId, required this.postId});

  final int groupId;
  final int postId;

  @override
  bool operator ==(Object other) {
    return other is PostModerationReviewKey &&
        other.groupId == groupId &&
        other.postId == postId;
  }

  @override
  int get hashCode => Object.hash(groupId, postId);
}
