import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';
import 'package:red_vecinal/features/posts/data/models/post_moderation_review_state.dart';

import 'post_test_support.dart';

void main() {
  test('propuesta nueva lista para revisión', () {
    final detail = PostDetail.fromJson(pendingQueuePostJson(id: 1));
    final state = PostModerationReviewState.fromDetail(
      detail: detail,
      expectedGroupId: 5,
    );

    expect(state.isReady, isTrue);
    expect(state.review!.pendingTitle, 'Propuesta pendiente');
    expect(state.review!.isAmendment, isFalse);
  });

  test('enmienda separa publicado y pendiente', () {
    final detail = PostDetail.fromJson(pendingAmendmentPostJson(id: 2));
    final state = PostModerationReviewState.fromDetail(
      detail: detail,
      expectedGroupId: 5,
    );

    expect(state.isReady, isTrue);
    expect(state.review!.isAmendment, isTrue);
    expect(state.review!.pendingTitle, 'Título enmienda');
    expect(state.review!.publishedTitle, 'Título publicado');
  });

  test('sin pending_content', () {
    final detail = sampleCommunityPostDetail();
    final state = PostModerationReviewState.fromDetail(
      detail: detail,
      expectedGroupId: 2,
    );

    expect(state.outcome, PostModerationReviewOutcome.resolved);
  });

  test('junta incorrecta', () {
    final detail = PostDetail.fromJson(pendingQueuePostJson(id: 3));
    final state = PostModerationReviewState.fromDetail(
      detail: detail,
      expectedGroupId: 99,
    );

    expect(state.outcome, PostModerationReviewOutcome.wrongNeighborhoodGroup);
  });

  test('publicación municipal', () {
    final state = PostModerationReviewState.fromDetail(
      detail: sampleMunicipalPostDetail(),
      expectedGroupId: 2,
    );

    expect(state.outcome, PostModerationReviewOutcome.notCommunityPost);
  });

  test('ya resuelta sin enmienda', () {
    final json = Map<String, dynamic>.from(pendingQueuePostJson(id: 4));
    json['status'] = 'published';
    json['pending_content'] = null;
    json['has_pending_amendment'] = false;
    json['content'] = {
      'revision_id': 1,
      'title': 'Publicado',
      'body': 'Listo',
      'body_html': '<p>Listo</p>',
    };
    final detail = PostDetail.fromJson(json);
    final state = PostModerationReviewState.fromDetail(
      detail: detail,
      expectedGroupId: 5,
    );

    expect(state.outcome, PostModerationReviewOutcome.resolved);
  });
}
