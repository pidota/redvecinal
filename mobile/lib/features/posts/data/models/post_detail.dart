import 'feed_post.dart';

class PostDetailContent {
  const PostDetailContent({
    required this.revisionId,
    required this.title,
    required this.body,
    this.bodyHtml,
  });

  factory PostDetailContent.fromJson(Map<String, dynamic> json) {
    return PostDetailContent(
      revisionId: json['revision_id'] as int,
      title: json['title'] as String,
      body: json['body'] as String,
      bodyHtml: json['body_html'] as String?,
    );
  }

  final int revisionId;
  final String title;
  final String body;
  final String? bodyHtml;

  /// Texto seguro para UI: sin renderer HTML aprobado (5.4D-3).
  String get displayText => PostDetail.plainTextForDisplay(body, bodyHtml);
}

class PostAttachment {
  const PostAttachment({
    required this.id,
    required this.revisionId,
    required this.originalDisplayName,
    required this.mimeType,
    required this.sizeBytes,
    required this.downloadUrl,
  });

  factory PostAttachment.fromJson(Map<String, dynamic> json) {
    return PostAttachment(
      id: json['id'] as int,
      revisionId: json['revision_id'] as int,
      originalDisplayName: json['original_display_name'] as String,
      mimeType: json['mime_type'] as String,
      sizeBytes: json['size_bytes'] as int? ?? 0,
      downloadUrl: json['download_url'] as String,
    );
  }

  final int id;
  final int revisionId;
  final String originalDisplayName;
  final String mimeType;
  final int sizeBytes;
  final String downloadUrl;

  String get sanitizedFileName =>
      PostAttachment.sanitizeFileName(originalDisplayName);

  static String sanitizeFileName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return 'adjunto';
    }
    final base = trimmed.split(RegExp(r'[/\\]')).last;
    final safe = base.replaceAll(RegExp(r'[^\w.\- áéíóúÁÉÍÓÚñÑ]+'), '_');
    if (safe.contains('..')) {
      return 'adjunto';
    }
    return safe.isEmpty ? 'adjunto' : safe;
  }

  /// Ruta relativa al [baseUrl] de Dio (`.../api/v1`).
  String get relativeDownloadPath {
    const apiPrefix = '/api/v1';
    if (downloadUrl.startsWith(apiPrefix)) {
      return downloadUrl.substring(apiPrefix.length);
    }
    if (downloadUrl.startsWith('/')) {
      return downloadUrl;
    }
    return downloadUrl;
  }

  String formattedSize() {
    if (sizeBytes < 1024) {
      return '$sizeBytes B';
    }
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class PostDetail {
  const PostDetail({
    required this.id,
    required this.postKind,
    required this.status,
    required this.publishedAt,
    required this.author,
    required this.neighborhoodGroup,
    required this.municipality,
    required this.category,
    required this.content,
    required this.engagement,
    required this.attachments,
  });

  factory PostDetail.fromJson(Map<String, dynamic> json) {
    final groupRaw = json['neighborhood_group'];
    final municipalityRaw = json['municipality'];
    final categoryRaw = json['category'];
    final authorRaw = json['author'];
    final contentRaw = json['content'];
    final engagementRaw = json['engagement'];
    final attachmentsRaw = json['attachments'];

    return PostDetail(
      id: json['id'] as int,
      postKind: json['post_kind'] as String,
      status: json['status'] as String,
      publishedAt: _parseDateTime(json['published_at'] as String?),
      author:
          authorRaw is Map<String, dynamic>
              ? FeedPostAuthor.fromJson(authorRaw)
              : const FeedPostAuthor(id: 0, name: 'Desconocido'),
      neighborhoodGroup:
          groupRaw is Map<String, dynamic>
              ? FeedPostGroupRef.fromJson(groupRaw)
              : null,
      municipality:
          municipalityRaw is Map<String, dynamic>
              ? FeedPostMunicipalityRef.fromJson(municipalityRaw)
              : null,
      category:
          categoryRaw is Map<String, dynamic>
              ? FeedPostCategoryRef.fromJson(categoryRaw)
              : null,
      content:
          contentRaw is Map<String, dynamic>
              ? PostDetailContent.fromJson(contentRaw)
              : null,
      engagement:
          engagementRaw is Map<String, dynamic>
              ? FeedPostEngagement.fromJson(engagementRaw)
              : const FeedPostEngagement(commentsCount: 0, reactionsCount: 0),
      attachments:
          attachmentsRaw is List
              ? attachmentsRaw
                  .whereType<Map<String, dynamic>>()
                  .map(PostAttachment.fromJson)
                  .toList()
              : const [],
    );
  }

  final int id;
  final String postKind;
  final String status;
  final DateTime? publishedAt;
  final FeedPostAuthor author;
  final FeedPostGroupRef? neighborhoodGroup;
  final FeedPostMunicipalityRef? municipality;
  final FeedPostCategoryRef? category;
  final PostDetailContent? content;
  final FeedPostEngagement engagement;
  final List<PostAttachment> attachments;

  bool get isMunicipal => postKind == 'municipal';

  String get scopeLabel {
    if (isMunicipal) {
      return municipality?.name ?? 'Comunicado municipal';
    }
    return neighborhoodGroup?.name ?? 'Junta vecinal';
  }

  String get title => content?.title ?? 'Sin título';

  String get bodyDisplay => content?.displayText ?? '';

  static String plainTextForDisplay(String? body, String? bodyHtml) {
    if (body != null && body.trim().isNotEmpty) {
      return body.trim();
    }
    if (bodyHtml == null || bodyHtml.trim().isEmpty) {
      return '';
    }
    return bodyHtml
        .replaceAll(RegExp(r'<[^>]*>', multiLine: true), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static DateTime? _parseDateTime(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }
}
