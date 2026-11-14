class PostReactionRecord {
  const PostReactionRecord({
    required this.id,
    required this.postId,
    required this.type,
  });

  factory PostReactionRecord.fromJson(Map<String, dynamic> json) {
    return PostReactionRecord(
      id: json['id'] as int,
      postId: json['post_id'] as int,
      type: json['type'] as String? ?? 'like',
    );
  }

  final int id;
  final int postId;
  final String type;
}
