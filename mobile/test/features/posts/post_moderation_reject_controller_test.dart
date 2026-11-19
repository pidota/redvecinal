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
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

const _groupId = 5;
const _postId = 1;

PostModerationReviewKey _key(int postId) =>
    PostModerationReviewKey(groupId: _groupId, postId: postId);

ProviderContainer moderationContainer(FakePostGateway gateway) {
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

PostDetail rejectedDetail(int id) {
  final json = Map<String, dynamic>.from(pendingQueuePostJson(id: id));
  final pending = json['pending_content'] as Map<String, dynamic>?;
  json['status'] = 'rejected';
  json['pending_content'] = null;
  json['has_pending_amendment'] = false;
  json['content'] =
      pending == null
          ? null
          : {
            'revision_id': 99,
            'title': pending['title'],
            'body': 'rechazado',
            'body_html': '<p>rechazado</p>',
          };
  return PostDetail.fromJson(json);
}

void main() {
  test('reject 200 confirma', () async {
    final gateway = FakePostGateway(
      detailById: {
        _postId: PostDetail.fromJson(pendingQueuePostJson(id: _postId)),
      },
      rejectedDetailByPostId: {_postId: rejectedDetail(_postId)},
    );
    final c = moderationContainer(gateway);
    final keepAlive = c.listen(
      postModerationReviewControllerProvider(_key(_postId)),
      (_, __) {},
    );
    addTearDown(() {
      keepAlive.close();
      c.dispose();
    });

    await c.read(postModerationReviewControllerProvider(_key(_postId)).future);
    final result = await c
        .read(postModerationReviewControllerProvider(_key(_postId)).notifier)
        .rejectPublication('Motivo válido de rechazo.');

    expect(result, isA<PostModerationRejectSuccess>());
    expect(gateway.rejectPostCallCount, 1);
  });

  test('motivo vacío bloqueado localmente', () async {
    final gateway = FakePostGateway(
      detailById: {
        _postId: PostDetail.fromJson(pendingQueuePostJson(id: _postId)),
      },
    );
    final c = moderationContainer(gateway);
    addTearDown(c.dispose);

    await c.read(postModerationReviewControllerProvider(_key(_postId)).future);
    final result = await c
        .read(postModerationReviewControllerProvider(_key(_postId)).notifier)
        .rejectPublication('   ');

    expect(result, isA<PostModerationRejectValidationFailure>());
    expect(gateway.rejectPostCallCount, 0);
  });

  test('motivo mayor a 2000 bloqueado', () async {
    final gateway = FakePostGateway(
      detailById: {
        _postId: PostDetail.fromJson(pendingQueuePostJson(id: _postId)),
      },
    );
    final c = moderationContainer(gateway);
    addTearDown(c.dispose);

    await c.read(postModerationReviewControllerProvider(_key(_postId)).future);
    final result = await c
        .read(postModerationReviewControllerProvider(_key(_postId)).notifier)
        .rejectPublication('x' * 2001);

    expect(result, isA<PostModerationRejectValidationFailure>());
  });

  test('timeout reject incierto bloquea approve', () async {
    final gateway = FakePostGateway(
      detailById: {
        _postId: PostDetail.fromJson(pendingQueuePostJson(id: _postId)),
      },
      rejectFailureByPostId: {_postId: const ApiTimeoutFailure()},
    );
    final c = moderationContainer(gateway);
    final keepAlive = c.listen(
      postModerationReviewControllerProvider(_key(_postId)),
      (_, __) {},
    );
    addTearDown(() {
      keepAlive.close();
      c.dispose();
    });

    await c.read(postModerationReviewControllerProvider(_key(_postId)).future);
    await c
        .read(postModerationReviewControllerProvider(_key(_postId)).notifier)
        .rejectPublication('Motivo claro.');

    final approve =
        await c
            .read(
              postModerationReviewControllerProvider(_key(_postId)).notifier,
            )
            .approvePublication();
    expect(approve, isA<PostModerationApproveBlocked>());
  });

  test('approve en curso bloquea reject', () async {
    final gateway = FakePostGateway(
      detailById: {
        _postId: PostDetail.fromJson(pendingQueuePostJson(id: _postId)),
      },
      approveDelayMs: 50,
    );
    final c = moderationContainer(gateway);
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
    final approveFuture = notifier.approvePublication();
    final reject = await notifier.rejectPublication('Motivo');
    expect(reject, isA<PostModerationRejectInFlight>());
    await approveFuture;
  });

  test('reject en curso bloquea approve', () async {
    final gateway = FakePostGateway(
      detailById: {
        _postId: PostDetail.fromJson(pendingQueuePostJson(id: _postId)),
      },
      rejectDelayMs: 50,
    );
    final c = moderationContainer(gateway);
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
    final rejectFuture = notifier.rejectPublication('Motivo de rechazo');
    final approve = await notifier.approvePublication();
    expect(approve, isA<PostModerationApproveInFlight>());
    await rejectFuture;
  });

  test('approve incierto bloquea reject', () async {
    final gateway = FakePostGateway(
      detailById: {
        _postId: PostDetail.fromJson(pendingQueuePostJson(id: _postId)),
      },
    );
    final c = moderationContainer(gateway);
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
    final epoch = c.read(authControllerProvider.notifier).sessionEpoch;
    final gen = persistence.beginDecisionAttempt(
      userId: 1,
      sessionEpoch: epoch,
      postId: _postId,
      pendingRevisionId: 10,
      decisionKind: PostModerationDecisionKind.approve,
    );
    persistence.promoteToOutcomeUncertainIfMatching(_postId, gen as int);
    c
        .read(postModerationReviewControllerProvider(_key(_postId)).notifier)
        .state = AsyncValue.data(
      c
          .read(postModerationReviewControllerProvider(_key(_postId)))
          .value!
          .copyWith(approveUncertain: true),
    );

    final reject = await c
        .read(postModerationReviewControllerProvider(_key(_postId)).notifier)
        .rejectPublication('Motivo');
    expect(reject, isA<PostModerationRejectBlocked>());
  });

  test('422 dominio sin auto-retry', () async {
    final gateway = FakePostGateway(
      detailById: {
        _postId: PostDetail.fromJson(pendingQueuePostJson(id: _postId)),
      },
      rejectFailureByPostId: {
        _postId: const ApiValidationFailure({}, 'La revisión ya fue resuelta.'),
      },
    );
    final c = moderationContainer(gateway);
    final keepAlive = c.listen(
      postModerationReviewControllerProvider(_key(_postId)),
      (_, __) {},
    );
    addTearDown(() {
      keepAlive.close();
      c.dispose();
    });

    await c.read(postModerationReviewControllerProvider(_key(_postId)).future);
    final result = await c
        .read(postModerationReviewControllerProvider(_key(_postId)).notifier)
        .rejectPublication('Motivo');
    expect(result, isA<PostModerationRejectFailure>());
    expect(gateway.rejectPostCallCount, 1);
  });
}
