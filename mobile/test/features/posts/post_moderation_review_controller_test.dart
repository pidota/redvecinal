import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/application/post_moderation_review_controller.dart';
import 'package:red_vecinal/features/posts/application/post_moderation_review_key.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';
import 'package:red_vecinal/features/posts/data/models/post_moderation_review_state.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

const _groupId = 5;

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

void main() {
  test('carga propuesta nueva', () async {
    final gateway = FakePostGateway(
      detailById: {1: PostDetail.fromJson(pendingQueuePostJson(id: 1))},
    );
    final c = moderationReviewContainer(gateway);
    addTearDown(c.dispose);

    final state = await c.read(
      postModerationReviewControllerProvider(_key(1)).future,
    );
    expect(state.isReady, isTrue);
    expect(state.review!.pendingBody, contains('moderación'));
  });

  test('error 403', () async {
    final gateway = FakePostGateway(
      detailFailureById: {1: const ApiForbiddenFailure()},
    );
    final c = moderationReviewContainer(gateway);

    expect(
      c.read(postModerationReviewControllerProvider(_key(1)).future),
      throwsA(isA<ApiForbiddenFailure>()),
    );
    c.dispose();
  });

  test('error 404', () async {
    final gateway = FakePostGateway(
      detailFailureById: {1: const ApiNotFoundFailure()},
    );
    final c = moderationReviewContainer(gateway);

    expect(
      c.read(postModerationReviewControllerProvider(_key(1)).future),
      throwsA(isA<ApiNotFoundFailure>()),
    );
    c.dispose();
  });

  test('error 500', () async {
    final gateway = FakePostGateway(
      detailFailureById: {1: const ApiServerFailure()},
    );
    final c = moderationReviewContainer(gateway);

    expect(
      c.read(postModerationReviewControllerProvider(_key(1)).future),
      throwsA(isA<ApiServerFailure>()),
    );
    c.dispose();
  });

  test('timeout en refresh', () async {
    final gateway = FakePostGateway(
      detailById: {1: PostDetail.fromJson(pendingQueuePostJson(id: 1))},
      detailDelayMs: 0,
    );
    final c = moderationReviewContainer(gateway);
    final keepAlive = c.listen(
      postModerationReviewControllerProvider(_key(1)),
      (_, __) {},
    );
    addTearDown(() {
      keepAlive.close();
      c.dispose();
    });

    await c.read(postModerationReviewControllerProvider(_key(1)).future);
    gateway.detailFailureById = {1: const ApiTimeoutFailure()};
    final notifier = c.read(
      postModerationReviewControllerProvider(_key(1)).notifier,
    );
    await notifier.refresh();
    final async = c.read(postModerationReviewControllerProvider(_key(1)));
    expect(async.hasError, isTrue);
    expect(async.error, isA<ApiTimeoutFailure>());
  });

  test('retry tras error', () async {
    final gateway = FakePostGateway(
      detailFailureById: {1: const ApiTimeoutFailure()},
    );
    final c = moderationReviewContainer(gateway);
    final keepAlive = c.listen(
      postModerationReviewControllerProvider(_key(1)),
      (_, __) {},
    );
    addTearDown(() {
      keepAlive.close();
      c.dispose();
    });

    await expectLater(
      c.read(postModerationReviewControllerProvider(_key(1)).future),
      throwsA(isA<ApiTimeoutFailure>()),
    );

    gateway.detailFailureById = null;
    gateway.detailById = {1: PostDetail.fromJson(pendingQueuePostJson(id: 1))};
    await c
        .read(postModerationReviewControllerProvider(_key(1)).notifier)
        .refresh();
    expect(
      c.read(postModerationReviewControllerProvider(_key(1))).value!.isReady,
      isTrue,
    );
  });

  test('logout durante carga', () async {
    final gateway = FakePostGateway(
      detailDelayMs: 80,
      detailById: {1: PostDetail.fromJson(pendingQueuePostJson(id: 1))},
    );
    final c = moderationReviewContainer(gateway);
    final keepAlive = c.listen(
      postModerationReviewControllerProvider(_key(1)),
      (_, __) {},
    );
    addTearDown(() {
      keepAlive.close();
      c.dispose();
    });

    final future = c.read(
      postModerationReviewControllerProvider(_key(1)).future,
    );
    await c.read(authControllerProvider.notifier).logout(localOnly: true);
    await expectLater(future, throwsA(isA<StateError>()));
  });

  test('cambio de postId aísla providers', () async {
    final gateway = FakePostGateway(
      detailById: {
        1: PostDetail.fromJson(pendingQueuePostJson(id: 1, title: 'Uno')),
        2: PostDetail.fromJson(pendingQueuePostJson(id: 2, title: 'Dos')),
      },
    );
    final c = moderationReviewContainer(gateway);
    addTearDown(c.dispose);

    final a = await c.read(
      postModerationReviewControllerProvider(_key(1)).future,
    );
    final b = await c.read(
      postModerationReviewControllerProvider(_key(2)).future,
    );
    expect(a.review!.pendingTitle, 'Uno');
    expect(b.review!.pendingTitle, 'Dos');
  });

  test('respuesta obsoleta tras refresh', () async {
    final gateway = FakePostGateway(
      detailDelayMs: 80,
      detailById: {
        1: PostDetail.fromJson(pendingQueuePostJson(id: 1, title: 'Tardío')),
      },
    );
    final c = moderationReviewContainer(gateway);
    final keepAlive = c.listen(
      postModerationReviewControllerProvider(_key(1)),
      (_, __) {},
    );
    addTearDown(() {
      keepAlive.close();
      c.dispose();
    });

    await c.read(postModerationReviewControllerProvider(_key(1)).future);

    gateway.detailById = {
      1: PostDetail.fromJson(pendingQueuePostJson(id: 1, title: 'Actualizado')),
    };
    gateway.detailDelayMs = 0;

    final slowRefresh =
        c
            .read(postModerationReviewControllerProvider(_key(1)).notifier)
            .refresh();
    await c
        .read(postModerationReviewControllerProvider(_key(1)).notifier)
        .refresh();
    await slowRefresh;

    final title =
        c
            .read(postModerationReviewControllerProvider(_key(1)))
            .value
            ?.review
            ?.pendingTitle;
    expect(title, 'Actualizado');
  });

  test('propuesta resuelta en GET', () async {
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail(id: 1)},
    );
    const resolvedKey = PostModerationReviewKey(groupId: 2, postId: 1);
    final c = moderationReviewContainer(gateway);
    addTearDown(c.dispose);

    final state = await c.read(
      postModerationReviewControllerProvider(resolvedKey).future,
    );
    expect(state.outcome, PostModerationReviewOutcome.resolved);
  });
}
