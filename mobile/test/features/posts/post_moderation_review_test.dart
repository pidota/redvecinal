import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/posts/data/models/feed_post.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';
import 'package:red_vecinal/features/posts/data/models/post_moderation_review.dart';

import 'post_test_support.dart';

void main() {
  test('propuesta nueva usa pending_content y no working_content', () {
    final post = FeedPost.fromJson(pendingQueuePostJson(id: 12));
    expect(PostModerationReview.isReviewable(post), isTrue);

    final review = PostModerationReview.fromFeedPost(post);
    expect(review, isNotNull);
    expect(review!.isAmendment, isFalse);
    expect(review.pendingTitle, 'Propuesta pendiente');
    expect(review.publishedTitle, isNull);
    expect(review.pendingAttachments, hasLength(1));
    expect(review.pendingAttachments.first.revisionId, 120);
    expect(review.publishedAttachments, isEmpty);
    expect(post.workingContent, isNull);
  });

  test('enmienda expone contenido publicado y pendiente por separado', () {
    final post = FeedPost.fromJson(pendingAmendmentPostJson(id: 30));
    final review = PostModerationReview.fromFeedPost(post);

    expect(review, isNotNull);
    expect(review!.isAmendment, isTrue);
    expect(review.pendingTitle, 'Título enmienda');
    expect(review.publishedTitle, 'Título publicado');
    expect(
      review.pendingAttachments.single.originalDisplayName,
      'enmienda.pdf',
    );
    expect(review.publishedAttachments.single.originalDisplayName, 'vivo.pdf');
    expect(review.pendingAttachments.first.revisionId, 51);
    expect(review.publishedAttachments.first.revisionId, 50);
  });

  test('sin pending_content no es revisable', () {
    final post = sampleCommunityPost();
    expect(PostModerationReview.isReviewable(post), isFalse);
    expect(PostModerationReview.fromFeedPost(post), isNull);
  });

  test('fromPostDetail usa pending_content sobre content', () {
    final detail = PostDetail.fromJson(pendingAmendmentPostJson(id: 40));
    final review = PostModerationReview.fromPostDetail(detail);

    expect(review, isNotNull);
    expect(review!.pendingTitle, 'Título enmienda');
    expect(review.pendingBody, contains('enmienda'));
    expect(review.publishedTitle, 'Título publicado');
    expect(detail.content!.title, isNot(review.pendingTitle));
  });
}
