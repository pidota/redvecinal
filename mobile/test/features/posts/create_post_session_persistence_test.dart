import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/posts/application/create_post_controller.dart';
import 'package:red_vecinal/features/posts/application/create_post_session_persistence.dart';
import 'package:red_vecinal/features/posts/application/draft_recovery_controller.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

void main() {
  ProviderContainer container(FakePostGateway gateway) {
    return ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        postRepositoryProvider.overrideWithValue(gateway),
        authControllerProvider.overrideWith(
          AuthenticatedBootAuthController.new,
        ),
      ],
    );
  }

  test('incierto persiste al desmontar y remontar controlador', () async {
    final gateway = FakePostGateway(createPostThrowsRaw: true);
    final c = container(gateway);
    addTearDown(c.dispose);

    await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );
    expect(
      c.read(createPostSessionPersistenceProvider).uncertainCreate,
      isTrue,
    );

    c.invalidate(createPostControllerProvider);
    final remounted = c.read(createPostControllerProvider);
    expect(remounted.uncertainCreate, isTrue);
    expect(remounted.blocksFullSend, isTrue);

    final second = await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T2',
          body: 'B2',
        );
    expect(second, isA<CreatePostSendUncertain>());
    expect(gateway.createPostCallCount, 1);
  });

  test('logout limpia incertidumbre persistida', () async {
    final gateway = FakePostGateway(createPostThrowsRaw: true);
    final c = container(gateway);
    addTearDown(c.dispose);

    await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );
    await c.read(authControllerProvider.notifier).logout(localOnly: true);
    expect(
      c.read(createPostSessionPersistenceProvider).uncertainCreate,
      isFalse,
    );
    c.invalidate(createPostControllerProvider);
    expect(c.read(createPostControllerProvider).blocksFullSend, isFalse);
  });

  test('usuario B no hereda incertidumbre de A', () async {
    final gateway = FakePostGateway(createPostThrowsRaw: true);
    final c = container(gateway);
    addTearDown(c.dispose);

    await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );
    await c.read(authControllerProvider.notifier).logout(localOnly: true);
    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(id: 50, email: 'b@test.com'),
    );

    expect(
      c.read(createPostSessionPersistenceProvider).uncertainCreate,
      isFalse,
    );
    await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'Nuevo',
          body: 'B',
        );
    expect(gateway.createPostCallCount, 2);
  });

  test('AuthState sin cambio de epoch mantiene bloqueo incierto', () async {
    final gateway = FakePostGateway(createPostThrowsRaw: true);
    final c = container(gateway);
    addTearDown(c.dispose);

    await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );
    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(),
    );
    c.invalidate(createPostSessionEpochProvider);
    expect(c.read(createPostControllerProvider).uncertainCreate, isTrue);
    expect(c.read(createPostSessionPersistenceProvider).blocksFullSend, isTrue);
  });

  test('fallo en recuperación no limpia incertidumbre', () async {
    final gateway = FakePostGateway(
      createPostThrowsRaw: true,
      myPostsFailure: const ApiNetworkFailure(),
    );
    final c = container(gateway);
    addTearDown(c.dispose);

    await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );
    await c.read(draftRecoveryControllerProvider.notifier).loadNextPage();
    expect(
      c.read(createPostSessionPersistenceProvider).uncertainCreate,
      isTrue,
    );
  });

  test('respuesta tardía de A no desbloquea B', () async {
    final gateway = FakePostGateway(createPostDelayMs: 100);
    final c = container(gateway);
    addTearDown(c.dispose);

    final op = c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );
    await c.read(authControllerProvider.notifier).logout(localOnly: true);
    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(id: 2, email: 'b@test.com'),
    );
    await op;

    expect(
      c.read(createPostSessionPersistenceProvider).uncertainCreate,
      isFalse,
    );
    await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'B solo',
          body: 'X',
        );
    expect(gateway.createPostCallCount, 2);
  });

  test('confirmedDraftId persiste al remontar y solo submit', () async {
    final gateway = FakePostGateway(
      submitFailureByPostId: {901: const ApiNetworkFailure()},
    );
    final c = container(gateway);
    addTearDown(c.dispose);

    await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );
    c.invalidate(createPostControllerProvider);
    expect(c.read(createPostControllerProvider).confirmedDraftId, 901);
    expect(c.read(createPostSessionPersistenceProvider).confirmedDraftId, 901);

    gateway.submitFailureByPostId = null;
    final retry =
        await c.read(createPostControllerProvider.notifier).retrySubmitOnly();
    expect(retry, isA<CreatePostSendSuccess>());
    expect(gateway.createPostCallCount, 1);
    expect(gateway.submitPostCallCount, 2);
  });
}
