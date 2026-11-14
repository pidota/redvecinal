import 'feed_post.dart';

class PostComment {
  const PostComment({
    required this.id,
    required this.postId,
    required this.authorId,
    required this.body,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.municipalityId,
    this.author,
  });

  factory PostComment.fromJson(Map<String, dynamic> json) {
    final authorRaw = json['author'];
    return PostComment(
      id: json['id'] as int,
      postId: json['post_id'] as int,
      municipalityId: json['municipality_id'] as int?,
      authorId: json['author_id'] as int,
      author:
          authorRaw is Map<String, dynamic>
              ? FeedPostAuthor.fromJson(authorRaw)
              : null,
      body: json['body'] as String? ?? '',
      status: json['status'] as String? ?? 'visible',
      createdAt: _parseDateTime(json['created_at'] as String?),
      updatedAt: _parseDateTime(json['updated_at'] as String?),
    );
  }

  final int id;
  final int postId;
  final int? municipalityId;
  final int authorId;
  final FeedPostAuthor? author;
  final String body;
  final String status;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get authorDisplayName => author?.name ?? 'Vecino';

  /// Texto plano para UI (sin interpretar HTML).
  String get plainBody => body;

  static DateTime? _parseDateTime(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }
}
