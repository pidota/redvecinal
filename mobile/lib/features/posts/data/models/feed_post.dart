class FeedPostAuthor {
  const FeedPostAuthor({required this.id, required this.name});

  factory FeedPostAuthor.fromJson(Map<String, dynamic> json) {
    return FeedPostAuthor(id: json['id'] as int, name: json['name'] as String);
  }

  final int id;
  final String name;
}

class FeedPostGroupRef {
  const FeedPostGroupRef({
    required this.id,
    required this.name,
    required this.slug,
  });

  factory FeedPostGroupRef.fromJson(Map<String, dynamic> json) {
    return FeedPostGroupRef(
      id: json['id'] as int,
      name: json['name'] as String,
      slug: json['slug'] as String,
    );
  }

  final int id;
  final String name;
  final String slug;
}

class FeedPostMunicipalityRef {
  const FeedPostMunicipalityRef({
    required this.id,
    required this.name,
    required this.slug,
  });

  factory FeedPostMunicipalityRef.fromJson(Map<String, dynamic> json) {
    return FeedPostMunicipalityRef(
      id: json['id'] as int,
      name: json['name'] as String,
      slug: json['slug'] as String,
    );
  }

  final int id;
  final String name;
  final String slug;
}

class FeedPostCategoryRef {
  const FeedPostCategoryRef({
    required this.id,
    required this.slug,
    required this.name,
  });

  factory FeedPostCategoryRef.fromJson(Map<String, dynamic> json) {
    return FeedPostCategoryRef(
      id: json['id'] as int,
      slug: json['slug'] as String,
      name: json['name'] as String,
    );
  }

  final int id;
  final String slug;
  final String name;
}

class FeedPostContent {
  const FeedPostContent({
    required this.revisionId,
    required this.title,
    required this.body,
  });

  factory FeedPostContent.fromJson(Map<String, dynamic> json) {
    return FeedPostContent(
      revisionId: json['revision_id'] as int,
      title: json['title'] as String,
      body: json['body'] as String,
    );
  }

  final int revisionId;
  final String title;
  final String body;
}

class FeedPostEngagement {
  const FeedPostEngagement({
    required this.commentsCount,
    required this.reactionsCount,
    this.myReactionType,
  });

  factory FeedPostEngagement.fromJson(Map<String, dynamic> json) {
    final myReaction = json['my_reaction'];
    String? type;
    if (myReaction is Map<String, dynamic>) {
      type = myReaction['type'] as String?;
    }

    return FeedPostEngagement(
      commentsCount: json['comments_count'] as int? ?? 0,
      reactionsCount: json['reactions_count'] as int? ?? 0,
      myReactionType: type,
    );
  }

  final int commentsCount;
  final int reactionsCount;
  final String? myReactionType;
}

class FeedPostAttachmentMeta {
  const FeedPostAttachmentMeta({
    required this.id,
    required this.originalDisplayName,
    required this.mimeType,
  });

  factory FeedPostAttachmentMeta.fromJson(Map<String, dynamic> json) {
    return FeedPostAttachmentMeta(
      id: json['id'] as int,
      originalDisplayName: json['original_display_name'] as String,
      mimeType: json['mime_type'] as String,
    );
  }

  final int id;
  final String originalDisplayName;
  final String mimeType;
}

class FeedPost {
  const FeedPost({
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

  factory FeedPost.fromJson(Map<String, dynamic> json) {
    final groupRaw = json['neighborhood_group'];
    final municipalityRaw = json['municipality'];
    final categoryRaw = json['category'];
    final authorRaw = json['author'];
    final contentRaw = json['content'];
    final engagementRaw = json['engagement'];
    final attachmentsRaw = json['attachments'];

    return FeedPost(
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
              ? FeedPostContent.fromJson(contentRaw)
              : null,
      engagement:
          engagementRaw is Map<String, dynamic>
              ? FeedPostEngagement.fromJson(engagementRaw)
              : const FeedPostEngagement(commentsCount: 0, reactionsCount: 0),
      attachments:
          attachmentsRaw is List
              ? attachmentsRaw
                  .whereType<Map<String, dynamic>>()
                  .map(FeedPostAttachmentMeta.fromJson)
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
  final FeedPostContent? content;
  final FeedPostEngagement engagement;
  final List<FeedPostAttachmentMeta> attachments;

  bool get isMunicipal => postKind == 'municipal';

  String get scopeLabel {
    if (isMunicipal) {
      return municipality?.name ?? 'Comunicado municipal';
    }
    return neighborhoodGroup?.name ?? 'Junta vecinal';
  }

  String get title => content?.title ?? 'Sin título';

  String get excerpt => excerptFromBody(content?.body);

  static String excerptFromBody(String? body, {int maxLength = 160}) {
    if (body == null || body.trim().isEmpty) {
      return '';
    }
    final normalized = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength)}…';
  }

  static DateTime? _parseDateTime(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }
}
