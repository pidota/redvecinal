import 'feed_post.dart';
import 'post_detail.dart';

/// Contenido que un moderador debe evaluar (propuesta nueva o enmienda).
///
/// Usa [FeedPost.pendingContent] y [FeedPost.pendingAttachments], no [FeedPost.workingContent].
class PostModerationReview {
  const PostModerationReview({
    required this.post,
    required this.pendingRevisionId,
    required this.pendingTitle,
    required this.pendingBody,
    required this.isAmendment,
    required this.pendingAttachments,
    this.publishedTitle,
    this.publishedBody,
    this.publishedAttachments = const [],
  });

  final FeedPost post;
  final int pendingRevisionId;
  final String pendingTitle;
  final String pendingBody;
  final bool isAmendment;
  final List<FeedPostAttachmentMeta> pendingAttachments;
  final String? publishedTitle;
  final String? publishedBody;
  final List<FeedPostAttachmentMeta> publishedAttachments;

  /// `true` si el recurso trae revisión pendiente visible para moderación.
  static bool isReviewable(FeedPost post) {
    return post.pendingContent != null;
  }

  /// Construye la vista de moderación o `null` si falta `pending_content`.
  static PostModerationReview? fromFeedPost(FeedPost post) {
    final pending = post.pendingContent;
    if (pending == null) {
      return null;
    }

    final isAmendment = post.hasPendingAmendment || post.status == 'published';
    final published = post.content;

    return PostModerationReview(
      post: post,
      pendingRevisionId: pending.revisionId,
      pendingTitle: pending.title,
      pendingBody: pending.body,
      isAmendment: isAmendment,
      pendingAttachments: post.pendingAttachments,
      publishedTitle: isAmendment ? published?.title : null,
      publishedBody: isAmendment ? published?.body : null,
      publishedAttachments: isAmendment ? post.attachments : const [],
    );
  }

  static PostModerationReview? fromPostDetail(PostDetail detail) {
    final pending = detail.pendingContent;
    if (pending == null) {
      return null;
    }

    final isAmendment =
        detail.hasPendingAmendment || detail.status == 'published';
    final published = detail.content;
    final post = _feedPostFromDetail(detail);

    return PostModerationReview(
      post: post,
      pendingRevisionId: pending.revisionId,
      pendingTitle: pending.title,
      pendingBody: pending.body,
      isAmendment: isAmendment,
      pendingAttachments: _attachmentMetaFromDetail(detail.pendingAttachments),
      publishedTitle: isAmendment ? published?.title : null,
      publishedBody: isAmendment ? published?.body : null,
      publishedAttachments:
          isAmendment
              ? _attachmentMetaFromDetail(detail.attachments)
              : const [],
    );
  }

  static FeedPost _feedPostFromDetail(PostDetail detail) {
    return FeedPost(
      id: detail.id,
      postKind: detail.postKind,
      status: detail.status,
      publishedAt: detail.publishedAt,
      hasPendingAmendment: detail.hasPendingAmendment,
      author: detail.author,
      neighborhoodGroup: detail.neighborhoodGroup,
      municipality: detail.municipality,
      category: detail.category,
      content:
          detail.content == null
              ? null
              : FeedPostContent(
                revisionId: detail.content!.revisionId,
                title: detail.content!.title,
                body: detail.content!.body,
              ),
      pendingContent:
          detail.pendingContent == null
              ? null
              : FeedPostContent(
                revisionId: detail.pendingContent!.revisionId,
                title: detail.pendingContent!.title,
                body: detail.pendingContent!.body,
              ),
      engagement: detail.engagement,
      attachments: _attachmentMetaFromDetail(detail.attachments),
      pendingAttachments: _attachmentMetaFromDetail(detail.pendingAttachments),
      workingContent: detail.workingContent,
    );
  }

  static List<FeedPostAttachmentMeta> _attachmentMetaFromDetail(
    List<PostAttachment> attachments,
  ) {
    return [
      for (final attachment in attachments)
        FeedPostAttachmentMeta(
          id: attachment.id,
          originalDisplayName: attachment.originalDisplayName,
          mimeType: attachment.mimeType,
          revisionId: attachment.revisionId,
          sizeBytes: attachment.sizeBytes,
          downloadUrl: attachment.downloadUrl,
        ),
    ];
  }
}
