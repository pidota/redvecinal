import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/application/post_moderation_approve_support.dart';
import 'package:red_vecinal/features/posts/application/post_moderation_review_controller.dart';
import 'package:red_vecinal/features/posts/application/post_moderation_review_key.dart';
import 'package:red_vecinal/features/posts/application/post_moderation_uncertain_approve_persistence.dart';
import 'package:red_vecinal/features/posts/application/post_moderation_uncertain_approve_record.dart';
import 'package:red_vecinal/features/posts/application/post_pending_queue_controller.dart';
import 'package:red_vecinal/features/posts/data/models/feed_post.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

const _groupId = 5;

PostModerationReviewKey _key(int postId) =>
    PostModerationReviewKey(groupId: _groupId, postId: postId);

ProviderContainer hardenedContainer(FakePostGateway gateway) {
  return ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(testAppConfig),
      authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
      tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      postRepositoryProvider.overrideWithValue(gateway),
      authControllerProvider.overrideWith(AuthenticatedBootAuthController.new),
    ],
  );
}

PostDetail resolvedApproved(int id) {
  final json = Map<String, dynamic>.from(pendingQueuePostJson(id: id));
  json['status'] = 'published';
  json['pending_content'] = null;
  json['content'] = {
    'revision_id': 99,
    'title': 'Publicado',
    'body': 'OK',
    'body_html': '<p>OK</p>',
  };
  return PostDetail.fromJson(json);
}

void main() {
  test('refresh durante POST conserva flags en vuelo', () async {
    final gateway = FakePostGateway(
      detailById: {1: PostDetail.fromJson(pendingQueuePostJson(id: 1))},
      approveDelayMs: 40,
    );
    final c = hardenedContainer(gateway);
    final keepReview = c.listen(
      postModerationReviewControllerProvider(_key(1)),
      (_, __) {},
    );
    final keepQueue = c.listen(
      postPendingQueueControllerProvider(_groupId),
      (_, __) {},
    );
    addTearDown(() {
      keepReview.close();
      keepQueue.close();
      c.dispose();
    });

    await c.read(postModerationReviewControllerProvider(_key(1)).future);
    final notifier = c.read(
      postModerationReviewControllerProvider(_key(1)).notifier,
    );
    final approveFuture = notifier.approvePublication();
    await notifier.refresh();

    final midState =
        c.read(postModerationReviewControllerProvider(_key(1))).value;
    expect(midState?.approveInFlight, isTrue);
    expect(midState?.approveUncertain, isFalse);

    gateway.approvedDetailByPostId = {1: resolvedApproved(1)};
    await approveFuture;
  });

  test('approve 200 invalida cola de pendientes', () async {
    final gateway = FakePostGateway(
      pendingPostsByGroupId: {
        _groupId: PaginatedFeedPosts(
          items: [FeedPost.fromJson(pendingQueuePostJson(id: 1))],
          currentPage: 1,
          lastPage: 1,
        ),
      },
      detailById: {1: PostDetail.fromJson(pendingQueuePostJson(id: 1))},
      approvedDetailByPostId: {1: resolvedApproved(1)},
    );
    final c = hardenedContainer(gateway);
    addTearDown(c.dispose);

    await c.read(postPendingQueueControllerProvider(_groupId).future);
    final listBefore = gateway.pendingPostsCallCount;

    await c.read(postModerationReviewControllerProvider(_key(1)).future);
    await c
        .read(postModerationReviewControllerProvider(_key(1)).notifier)
        .approvePublication();

    await c.read(postPendingQueueControllerProvider(_groupId).future);
    expect(gateway.pendingPostsCallCount, greaterThan(listBefore));
  });

  test('reject 200 invalida cola de pendientes', () async {
    final rejectedJson = Map<String, dynamic>.from(pendingQueuePostJson(id: 2));
    rejectedJson['status'] = 'rejected';
    rejectedJson['pending_content'] = null;

    final gateway = FakePostGateway(
      pendingPostsByGroupId: {
        _groupId: PaginatedFeedPosts(
          items: [FeedPost.fromJson(pendingQueuePostJson(id: 2))],
          currentPage: 1,
          lastPage: 1,
        ),
      },
      detailById: {2: PostDetail.fromJson(pendingQueuePostJson(id: 2))},
      rejectedDetailByPostId: {2: PostDetail.fromJson(rejectedJson)},
    );
    final c = hardenedContainer(gateway);
    addTearDown(c.dispose);

    await c.read(postPendingQueueControllerProvider(_groupId).future);
    final listBefore = gateway.pendingPostsCallCount;

    await c.read(postModerationReviewControllerProvider(_key(2)).future);
    await c
        .read(postModerationReviewControllerProvider(_key(2)).notifier)
        .rejectPublication('Motivo válido.');

    await c.read(postPendingQueueControllerProvider(_groupId).future);
    expect(gateway.pendingPostsCallCount, greaterThan(listBefore));
  });

  test('reconciliación con GET fallido mantiene incertidumbre', () async {
    final gateway = FakePostGateway(
      detailById: {1: PostDetail.fromJson(pendingQueuePostJson(id: 1))},
    );

    final c = hardenedContainer(gateway);
    final keepAlive = c.listen(
      postModerationReviewControllerProvider(_key(1)),
      (_, __) {},
    );
    addTearDown(() {
      keepAlive.close();
      c.dispose();
    });

    await c.read(postModerationReviewControllerProvider(_key(1)).future);
    final persistence = c.read(
      postModerationUncertainApprovePersistenceProvider.notifier,
    );
    final epoch = c.read(authControllerProvider.notifier).sessionEpoch;
    final gen = persistence.beginDecisionAttempt(
      userId: 1,
      sessionEpoch: epoch,
      postId: 1,
      pendingRevisionId: 10,
      decisionKind: PostModerationDecisionKind.reject,
    );
    persistence.promoteToOutcomeUncertainIfMatching(1, gen as int);
    c
        .read(postModerationReviewControllerProvider(_key(1)).notifier)
        .state = AsyncValue.data(
      c
          .read(postModerationReviewControllerProvider(_key(1)))
          .value!
          .copyWith(approveUncertain: true),
    );

    gateway.detailFailureById = {1: const ApiTimeoutFailure()};

    final reconcile =
        await c
            .read(postModerationReviewControllerProvider(_key(1)).notifier)
            .reconcileUncertainApprove();

    expect(reconcile, isA<PostModerationApproveReconcileGetFailed>());
    expect(
      c
          .read(postModerationReviewControllerProvider(_key(1)))
          .value!
          .approveUncertain,
      isTrue,
    );
  });

  test(
    'rechazo server 422 campo conserva motivo vía PostModerationRejectFailure',
    () async {
      final gateway = FakePostGateway(
        detailById: {1: PostDetail.fromJson(pendingQueuePostJson(id: 1))},
        rejectFailureByPostId: {
          1: const ApiValidationFailure({
            'rejection_reason': ['Motivo demasiado corto.'],
          }, 'Revisa el motivo.'),
        },
      );
      final c = hardenedContainer(gateway);
      addTearDown(c.dispose);

      await c.read(postModerationReviewControllerProvider(_key(1)).future);
      final result = await c
          .read(postModerationReviewControllerProvider(_key(1)).notifier)
          .rejectPublication('ok');

      expect(result, isA<PostModerationRejectFailure>());
      final failure = (result as PostModerationRejectFailure).failure;
      expect(failure is ApiValidationFailure, isTrue);
      expect(
        (failure as ApiValidationFailure).fieldErrors.containsKey(
          'rejection_reason',
        ),
        isTrue,
      );
    },
  );
}
