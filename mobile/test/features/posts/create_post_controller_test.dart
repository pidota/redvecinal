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
import 'package:red_vecinal/features/posts/application/feed_controller.dart';
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

  test('create → submit deja pending', () async {
    final gateway = FakePostGateway();
    final c = container(gateway);
    addTearDown(c.dispose);

    final result = await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'Título',
          body: 'Contenido',
        );

    expect(result, isA<CreatePostSendSuccess>());
    expect(gateway.createPostCallCount, 1);
    expect(gateway.submitPostCallCount, 1);
    final success = result as CreatePostSendSuccess;
    expect(success.detail.status, 'pending');
  });

  test('doble envío bloqueado', () async {
    final gateway = FakePostGateway(createPostDelayMs: 100);
    final c = container(gateway);
    addTearDown(c.dispose);

    final first = c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'A',
          body: 'B',
        );
    final second = c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'C',
          body: 'D',
        );
    await first;
    await second;
    expect(gateway.createPostCallCount, 1);
  });

  test('create fallido no llama submit', () async {
    final gateway = FakePostGateway(
      createPostFailure: const ApiForbiddenFailure(),
    );
    final c = container(gateway);
    addTearDown(c.dispose);

    final result = await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );

    expect(result, isA<CreatePostSendCreateFailed>());
    expect(gateway.createPostCallCount, 1);
    expect(gateway.submitPostCallCount, 0);
  });

  test('submit fallido conserva borrador y reintento solo submit', () async {
    final gateway = FakePostGateway(
      submitFailureByPostId: {901: const ApiNetworkFailure()},
    );
    final c = container(gateway);
    addTearDown(c.dispose);

    final first = await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );
    expect(first, isA<CreatePostSendDraftOnly>());
    expect(c.read(createPostControllerProvider).confirmedDraftId, 901);

    gateway.submitFailureByPostId = null;
    final retry =
        await c.read(createPostControllerProvider.notifier).retrySubmitOnly();
    expect(retry, isA<CreatePostSendSuccess>());
    expect(gateway.createPostCallCount, 1);
    expect(gateway.submitPostCallCount, 2);
  });

  test('borrador confirmado no duplica create', () async {
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
    await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T2',
          body: 'B2',
        );

    expect(gateway.createPostCallCount, 1);
    expect(gateway.submitPostCallCount, 2);
  });

  test('getPost pending confirma sin reenviar submit', () async {
    final gateway = FakePostGateway(
      detailById: {901: pendingPostDetail(id: 901)},
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

    final checked =
        await c
            .read(createPostControllerProvider.notifier)
            .refreshDraftStatusAndMaybeSubmit();
    expect(checked, isA<CreatePostSendSuccess>());
    expect(gateway.submitPostCallCount, 1);
  });

  test('logout durante create descarta resultado', () async {
    final gateway = FakePostGateway(createPostDelayMs: 80);
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
    final result = await op;
    expect(result, isA<CreatePostSendDiscarded>());
  });

  test('logout durante submit descarta', () async {
    final gateway = FakePostGateway(
      createPostDelayMs: 0,
      submitPostDelayMs: 80,
    );
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
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await c.read(authControllerProvider.notifier).logout(localOnly: true);
    final result = await op;
    expect(result, isA<CreatePostSendDiscarded>());
  });

  test('cambio de usuario descarta confirmación', () async {
    final gateway = FakePostGateway(submitPostDelayMs: 100);
    final c = container(gateway);
    addTearDown(c.dispose);

    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(id: 1),
    );
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
      sampleAuthUser(id: 99, email: 'otro@test.com'),
    );
    final result = await op;
    expect(result, isA<CreatePostSendDiscarded>());
  });

  test('no invalida feed tras envío', () async {
    final gateway = FakePostGateway();
    final c = container(gateway);
    addTearDown(c.dispose);
    c.listen(feedControllerProvider, (_, __) {});

    final callsBefore = gateway.callCount;
    await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );
    expect(gateway.callCount, callsBefore);
  });

  test('respuesta incierta en create', () async {
    final gateway = FakePostGateway(createPostThrowsRaw: true);
    final c = container(gateway);
    addTearDown(c.dispose);

    final result = await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );
    expect(result, isA<CreatePostSendUncertain>());
    expect(c.read(createPostControllerProvider).uncertainCreate, isTrue);
  });

  test('create incierto bloquea segundo create', () async {
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
    expect(c.read(createPostControllerProvider).uncertainCreate, isTrue);

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

  test('selección explícita enlaza borrador', () async {
    final gateway = FakePostGateway(
      createPostThrowsRaw: true,
      detailById: {
        77: draftPostDetail(
          id: 77,
          groupId: 2,
          categoryId: 2,
          title: 'Borrador',
          body: 'Cuerpo',
        ),
      },
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

    final linked = await c
        .read(createPostControllerProvider.notifier)
        .linkExplicitRecoveryDraft(77);
    expect(linked, isA<CreatePostSendDraftLinked>());
    expect(c.read(createPostControllerProvider).confirmedDraftId, 77);
    expect(c.read(createPostControllerProvider).uncertainCreate, isFalse);
    expect(gateway.createPostCallCount, 1);
  });

  test('no sustituye confirmedDraftId distinto', () async {
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
    expect(c.read(createPostControllerProvider).confirmedDraftId, 901);

    final deny = await c
        .read(createPostControllerProvider.notifier)
        .linkExplicitRecoveryDraft(50);
    expect(deny, isA<CreatePostSendCreateFailed>());
    expect(c.read(createPostControllerProvider).confirmedDraftId, 901);
  });

  test('pending explícito no confirma envío actual', () async {
    final gateway = FakePostGateway(
      createPostThrowsRaw: true,
      detailById: {88: pendingPostDetail(id: 88)},
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
    final result = await c
        .read(createPostControllerProvider.notifier)
        .linkExplicitRecoveryDraft(88);
    expect(result, isA<CreatePostSendAlreadyPending>());
    expect(c.read(createPostControllerProvider).confirmedDraftId, isNull);
    expect(
      c.read(createPostSessionPersistenceProvider).uncertainCreate,
      isTrue,
    );
    expect(c.read(createPostControllerProvider).uncertainCreate, isTrue);
  });

  test('AuthState sin cambio de epoch conserva confirmedDraftId', () async {
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
    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(),
    );
    c.invalidate(createPostSessionEpochProvider);
    expect(c.read(createPostControllerProvider).confirmedDraftId, 901);
  });

  test('logout durante enlace explícito descarta', () async {
    final gateway = FakePostGateway(
      createPostThrowsRaw: true,
      detailDelayMs: 80,
      detailById: {
        77: draftPostDetail(
          id: 77,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
    );
    final c = container(gateway);
    addTearDown(c.dispose);

    final op = c
        .read(createPostControllerProvider.notifier)
        .linkExplicitRecoveryDraft(77);
    await c.read(authControllerProvider.notifier).logout(localOnly: true);
    final result = await op;
    expect(result, isA<CreatePostSendDiscarded>());
  });

  test('isNeighborhoodGroupEligibleForPosting', () {
    expect(isNeighborhoodGroupEligibleForPosting('active'), isTrue);
    expect(isNeighborhoodGroupEligibleForPosting('suspended'), isFalse);
  });
}
