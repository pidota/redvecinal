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
import 'package:red_vecinal/features/posts/application/post_pending_queue_controller.dart';
import 'package:red_vecinal/features/posts/application/feed_controller.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

const _groupId = 5;
const _postId = 1;

PostModerationReviewKey _key(int postId) =>
    PostModerationReviewKey(groupId: _groupId, postId: postId);

ProviderContainer moderationReviewContainer(FakePostGateway gateway) {
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

PostDetail publishedAfterApprove(int id) {
  final json = Map<String, dynamic>.from(pendingQueuePostJson(id: id));
  final pending = json['pending_content'] as Map<String, dynamic>?;
  json['status'] = 'published';
  json['published_at'] = '2026-11-19T12:00:00+00:00';
  json['has_pending_amendment'] = false;
  json['content'] = {
    'revision_id': 501,
    'title': pending?['title'] ?? 'Propuesta pendiente',
    'body': pending?['body'] ?? 'Texto',
    'body_html': '<p>Texto</p>',
  };
  json['pending_content'] = null;
  json['pending_attachments'] = [];
  return PostDetail.fromJson(json);
}

void main() {
  test('approve 200 invalida cola y feed', () async {
    final approved = publishedAfterApprove(_postId);
    final gateway = FakePostGateway(
      detailById: {
        _postId: PostDetail.fromJson(pendingQueuePostJson(id: _postId)),
      },
      approvedDetailByPostId: {_postId: approved},
    );
    final c = moderationReviewContainer(gateway);
    final keepAlive = c.listen(
      postModerationReviewControllerProvider(_key(_postId)),
      (_, __) {},
    );
    addTearDown(() {
      keepAlive.close();
      c.dispose();
    });

    await c.read(postModerationReviewControllerProvider(_key(_postId)).future);
    c.listen(postPendingQueueControllerProvider(_groupId), (_, __) {});
    c.listen(feedControllerProvider, (_, __) {});

    final result =
        await c
            .read(
              postModerationReviewControllerProvider(_key(_postId)).notifier,
            )
            .approvePublication();

    expect(result, isA<PostModerationApproveSuccess>());
    expect(gateway.approvePostCallCount, 1);
    expect(
      c
          .read(postModerationReviewControllerProvider(_key(_postId)))
          .value!
          .isReady,
      isFalse,
    );
  });

  test('doble aprobación concurrente bloqueada', () async {
    final gateway = FakePostGateway(
      detailById: {
        _postId: PostDetail.fromJson(pendingQueuePostJson(id: _postId)),
      },
      approveDelayMs: 50,
    );
    final c = moderationReviewContainer(gateway);
    final keepAlive = c.listen(
      postModerationReviewControllerProvider(_key(_postId)),
      (_, __) {},
    );
    addTearDown(() {
      keepAlive.close();
      c.dispose();
    });

    await c.read(postModerationReviewControllerProvider(_key(_postId)).future);
    final notifier = c.read(
      postModerationReviewControllerProvider(_key(_postId)).notifier,
    );
    final first = notifier.approvePublication();
    final second = await notifier.approvePublication();
    expect(second, isA<PostModerationApproveInFlight>());
    await first;
  });

  test('timeout marca incertidumbre', () async {
    final gateway = FakePostGateway(
      detailById: {
        _postId: PostDetail.fromJson(pendingQueuePostJson(id: _postId)),
      },
      approveFailureByPostId: {_postId: const ApiTimeoutFailure()},
    );
    final c = moderationReviewContainer(gateway);
    final keepAlive = c.listen(
      postModerationReviewControllerProvider(_key(_postId)),
      (_, __) {},
    );
    addTearDown(() {
      keepAlive.close();
      c.dispose();
    });

    await c.read(postModerationReviewControllerProvider(_key(_postId)).future);
    final result =
        await c
            .read(
              postModerationReviewControllerProvider(_key(_postId)).notifier,
            )
            .approvePublication();

    expect(result, isA<PostModerationApproveUncertain>());
    expect(
      c
          .read(postModerationReviewControllerProvider(_key(_postId)))
          .value!
          .approveUncertain,
      isTrue,
    );
    expect(
      c
          .read(postModerationUncertainApprovePersistenceProvider)
          .recordForPost(_postId),
      isNotNull,
    );
  });

  test('422 dominio refresca sin auto-retry', () async {
    final gateway = FakePostGateway(
      detailById: {
        _postId: PostDetail.fromJson(pendingQueuePostJson(id: _postId)),
      },
      approveFailureByPostId: {
        _postId: const ApiValidationFailure(
          {},
          'La revisión ya no está pendiente.',
        ),
      },
    );
    final c = moderationReviewContainer(gateway);
    final keepAlive = c.listen(
      postModerationReviewControllerProvider(_key(_postId)),
      (_, __) {},
    );
    addTearDown(() {
      keepAlive.close();
      c.dispose();
    });

    await c.read(postModerationReviewControllerProvider(_key(_postId)).future);
    final result =
        await c
            .read(
              postModerationReviewControllerProvider(_key(_postId)).notifier,
            )
            .approvePublication();

    expect(result, isA<PostModerationApproveFailure>());
    expect(gateway.approvePostCallCount, 1);
  });

  test('403 marca sin autorización', () async {
    final gateway = FakePostGateway(
      detailById: {
        _postId: PostDetail.fromJson(pendingQueuePostJson(id: _postId)),
      },
      approveFailureByPostId: {_postId: const ApiForbiddenFailure()},
    );
    final c = moderationReviewContainer(gateway);
    final keepAlive = c.listen(
      postModerationReviewControllerProvider(_key(_postId)),
      (_, __) {},
    );
    addTearDown(() {
      keepAlive.close();
      c.dispose();
    });

    await c.read(postModerationReviewControllerProvider(_key(_postId)).future);
    final result =
        await c
            .read(
              postModerationReviewControllerProvider(_key(_postId)).notifier,
            )
            .approvePublication();

    expect(result, isA<PostModerationApproveFailure>());
    expect(
      c
          .read(postModerationReviewControllerProvider(_key(_postId)))
          .value!
          .approveForbidden,
      isTrue,
    );
  });

  test('reconciliación con revisión pendiente', () async {
    final gateway = FakePostGateway(
      detailById: {
        _postId: PostDetail.fromJson(pendingQueuePostJson(id: _postId)),
      },
    );
    final c = moderationReviewContainer(gateway);
    final keepAlive = c.listen(
      postModerationReviewControllerProvider(_key(_postId)),
      (_, __) {},
    );
    addTearDown(() {
      keepAlive.close();
      c.dispose();
    });

    await c.read(postModerationReviewControllerProvider(_key(_postId)).future);
    final persistence = c.read(
      postModerationUncertainApprovePersistenceProvider.notifier,
    );
    persistence.persistenceCommitEnabled = true;
    final gen = persistence.beginApproveAttempt(
      userId: 1,
      sessionEpoch: c.read(authControllerProvider.notifier).sessionEpoch,
      postId: _postId,
      pendingRevisionId: 10,
    );
    expect(gen, isNotNull);
    persistence.promoteToOutcomeUncertainIfMatching(_postId, gen as int);
    c
        .read(postModerationReviewControllerProvider(_key(_postId)).notifier)
        .state = AsyncValue.data(
      c
          .read(postModerationReviewControllerProvider(_key(_postId)))
          .value!
          .copyWith(approveUncertain: true),
    );

    final reconcile =
        await c
            .read(
              postModerationReviewControllerProvider(_key(_postId)).notifier,
            )
            .reconcileUncertainApprove();

    expect(reconcile, isA<PostModerationApproveReconcileStillPending>());
    expect(
      c
          .read(postModerationReviewControllerProvider(_key(_postId)))
          .value!
          .approveUncertain,
      isFalse,
    );
  });

  test('autor no puede aprobar propia publicación', () async {
    final json = Map<String, dynamic>.from(pendingQueuePostJson(id: _postId));
    json['author'] = {'id': 1, 'name': 'Mismo usuario'};
    final gateway = FakePostGateway(
      detailById: {_postId: PostDetail.fromJson(json)},
    );
    final c = moderationReviewContainer(gateway);
    addTearDown(c.dispose);

    await c.read(postModerationReviewControllerProvider(_key(_postId)).future);
    final result =
        await c
            .read(
              postModerationReviewControllerProvider(_key(_postId)).notifier,
            )
            .approvePublication();

    expect(result, isA<PostModerationApproveBlocked>());
    expect(gateway.approvePostCallCount, 0);
  });

  test('logout durante POST descarta', () async {
    final gateway = FakePostGateway(
      detailById: {
        _postId: PostDetail.fromJson(pendingQueuePostJson(id: _postId)),
      },
      approveDelayMs: 80,
    );
    final c = moderationReviewContainer(gateway);
    final keepAlive = c.listen(
      postModerationReviewControllerProvider(_key(_postId)),
      (_, __) {},
    );
    addTearDown(() {
      keepAlive.close();
      c.dispose();
    });

    await c.read(postModerationReviewControllerProvider(_key(_postId)).future);
    final future =
        c
            .read(
              postModerationReviewControllerProvider(_key(_postId)).notifier,
            )
            .approvePublication();
    await c.read(authControllerProvider.notifier).logout(localOnly: true);
    final result = await future;
    expect(result, isA<PostModerationApproveDiscarded>());
  });
}
