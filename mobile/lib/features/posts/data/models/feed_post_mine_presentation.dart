import 'feed_post.dart';

/// Títulos, resúmenes y etiquetas para listados propios ([FeedPost] con contexto autor).
/// No altera [FeedPost.title] / [FeedPost.excerpt] usados por el feed público.
class FeedPostMinePresentation {
  const FeedPostMinePresentation._();

  static bool canEditFromList(FeedPost post) {
    return post.status == 'draft' || post.status == 'rejected';
  }

  static String statusLabel(String status) {
    switch (status) {
      case 'draft':
        return 'Borrador';
      case 'pending':
        return 'En revisión';
      case 'published':
        return 'Publicada';
      case 'rejected':
        return 'Rechazada';
      case 'hidden':
        return 'Oculta';
      case 'archived':
        return 'Archivada';
      default:
        return _humanizeUnknownStatus(status);
    }
  }

  static String _humanizeUnknownStatus(String status) {
    final normalized = status.replaceAll('_', ' ').trim();
    if (normalized.isEmpty) {
      return 'Estado desconocido';
    }
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  static String listTitle(FeedPost post) {
    final title = _resolveTitle(post);
    return title ?? 'Sin título';
  }

  static String listExcerpt(FeedPost post) {
    final body = _resolveBody(post);
    return FeedPost.excerptFromBody(body);
  }

  static bool showsAmendmentHint(FeedPost post) {
    return post.status == 'published' && post.hasPendingAmendment;
  }

  static String? _resolveTitle(FeedPost post) {
    switch (post.status) {
      case 'draft':
      case 'rejected':
        return _firstNonEmpty([
          post.workingContent?.title,
          post.content?.title,
        ]);
      case 'pending':
        return _firstNonEmpty([
          post.pendingContent?.title,
          post.content?.title,
        ]);
      case 'published':
      case 'hidden':
      case 'archived':
        return _firstNonEmpty([
          post.content?.title,
          post.workingContent?.title,
          post.pendingContent?.title,
        ]);
      default:
        return _firstNonEmpty([
          post.content?.title,
          post.workingContent?.title,
          post.pendingContent?.title,
        ]);
    }
  }

  static String? _resolveBody(FeedPost post) {
    switch (post.status) {
      case 'draft':
      case 'rejected':
        return _firstNonEmpty([post.workingContent?.body, post.content?.body]);
      case 'pending':
        return _firstNonEmpty([post.pendingContent?.body, post.content?.body]);
      case 'published':
      case 'hidden':
      case 'archived':
        return _firstNonEmpty([post.content?.body, post.workingContent?.body]);
      default:
        return _firstNonEmpty([
          post.content?.body,
          post.workingContent?.body,
          post.pendingContent?.body,
        ]);
    }
  }

  static String? _firstNonEmpty(List<String?> candidates) {
    for (final raw in candidates) {
      if (raw == null) {
        continue;
      }
      final trimmed = raw.trim();
      if (trimmed.isNotEmpty) {
        return trimmed;
      }
    }
    return null;
  }
}
