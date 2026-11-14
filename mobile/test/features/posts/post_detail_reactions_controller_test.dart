import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/application/feed_controller.dart';
import 'package:red_vecinal/features/posts/application/post_detail_controller.dart';
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

  test('agregar like actualiza my_reaction', () async {
    final details = {1: detailWithEngagement(id: 1)};
    final gateway = FakePostGateway(
      detailById: details,
      onSetReaction: (postId, _) {
        details[postId] = detailWithEngagement(
          id: postId,
          reactionsCount: 1,
          myReactionType: 'like',
        );
      },
    );
    final c = container(gateway);
    addTearDown(c.dispose);
    c.listen(postDetailControllerProvider(1), (_, __) {});

    await c.read(postDetailControllerProvider(1).future);
    final err =
        await c
            .read(postDetailControllerProvider(1).notifier)
            .setLikeReaction();
    expect(err, isNull);
    expect(
      c.read(postDetailControllerProvider(1)).value!.engagement.hasLike,
      isTrue,
    );
    expect(gateway.setReactionCallCount, 1);
  });

  test('quitar like limpia reacción', () async {
    final details = {
      1: detailWithEngagement(id: 1, reactionsCount: 2, myReactionType: 'like'),
    };
    final gateway = FakePostGateway(
      detailById: details,
      onRemoveReaction: (postId) {
        details[postId] = detailWithEngagement(id: postId, reactionsCount: 1);
      },
    );
    final c = container(gateway);
    addTearDown(c.dispose);

    await c.read(postDetailControllerProvider(1).future);
    await c.read(postDetailControllerProvider(1).notifier).removeLikeReaction();
    expect(
      c.read(postDetailControllerProvider(1)).value!.engagement.hasLike,
      isFalse,
    );
  });

  test('cambio celebrate a like no incrementa contador optimista', () async {
    final details = {
      1: detailWithEngagement(
        id: 1,
        reactionsCount: 3,
        myReactionType: 'celebrate',
      ),
    };
    final gateway = FakePostGateway(
      detailById: details,
      onSetReaction: (id, _) {
        details[id] = detailWithEngagement(
          id: id,
          reactionsCount: 3,
          myReactionType: 'like',
        );
      },
    );
    final c = container(gateway);
    addTearDown(c.dispose);

    await c.read(postDetailControllerProvider(1).future);
    await c.read(postDetailControllerProvider(1).notifier).setLikeReaction();
    final engagement =
        c.read(postDetailControllerProvider(1)).value!.engagement;
    expect(engagement.reactionsCount, 3);
    expect(engagement.hasLike, isTrue);
  });

  test('doble tap bloqueado', () async {
    final gateway = FakePostGateway(
      detailById: {1: detailWithEngagement(id: 1)},
      reactionDelayMs: 120,
    );
    final c = container(gateway);
    addTearDown(c.dispose);

    await c.read(postDetailControllerProvider(1).future);
    final first =
        c.read(postDetailControllerProvider(1).notifier).setLikeReaction();
    final second =
        c.read(postDetailControllerProvider(1).notifier).setLikeReaction();
    await first;
    await second;
    expect(gateway.setReactionCallCount, 1);
  });

  test('fallo PUT restaura estado', () async {
    final gateway = FakePostGateway(
      detailById: {1: detailWithEngagement(id: 1, reactionsCount: 0)},
      setReactionFailureByPostId: {1: const ApiForbiddenFailure()},
    );
    final c = container(gateway);
    addTearDown(c.dispose);

    await c.read(postDetailControllerProvider(1).future);
    final before = c.read(postDetailControllerProvider(1)).value!.engagement;
    final err =
        await c
            .read(postDetailControllerProvider(1).notifier)
            .setLikeReaction();
    expect(err, isA<ApiForbiddenFailure>());
    expect(c.read(postDetailControllerProvider(1)).value!.engagement, before);
  });

  test('fallo DELETE restaura estado', () async {
    final gateway = FakePostGateway(
      detailById: {
        1: detailWithEngagement(
          id: 1,
          reactionsCount: 2,
          myReactionType: 'like',
        ),
      },
      removeReactionFailureByPostId: {1: const ApiNetworkFailure()},
    );
    final c = container(gateway);
    addTearDown(c.dispose);

    await c.read(postDetailControllerProvider(1).future);
    final before = c.read(postDetailControllerProvider(1)).value!.engagement;
    final err =
        await c
            .read(postDetailControllerProvider(1).notifier)
            .removeLikeReaction();
    expect(err, isA<ApiNetworkFailure>());
    expect(c.read(postDetailControllerProvider(1)).value!.engagement, before);
  });

  test(
    'respuesta tardía tras cambio de usuario no restaura snapshot previo',
    () async {
      final details = {
        1: detailWithEngagement(id: 1, reactionsCount: 0, myReactionType: null),
      };
      final gateway = FakePostGateway(
        detailById: details,
        reactionDelayMs: 80,
        onSetReaction: (id, _) {
          details[id] = detailWithEngagement(
            id: id,
            reactionsCount: 9,
            myReactionType: 'like',
          );
        },
      );
      final c = container(gateway);
      addTearDown(c.dispose);

      c.read(authControllerProvider.notifier).state = AuthAuthenticated(
        sampleAuthUser(id: 1),
      );
      final sub = c.listen(postDetailControllerProvider(1), (_, __) {});
      await c.read(postDetailControllerProvider(1).future);

      final op =
          c.read(postDetailControllerProvider(1).notifier).setLikeReaction();
      await c.read(authControllerProvider.notifier).logout(localOnly: true);
      c.read(authControllerProvider.notifier).state = AuthAuthenticated(
        sampleAuthUser(id: 99, email: 'nuevo@test.com'),
      );
      details[1] = detailWithEngagement(id: 1, reactionsCount: 2);
      await c.read(postDetailControllerProvider(1).future);
      await op;
      sub.close();

      final detail = c.read(postDetailControllerProvider(1)).valueOrNull;
      expect(detail?.engagement.reactionsCount, 2);
      expect(detail?.engagement.hasLike, isFalse);
    },
  );

  test('logout durante PUT descarta efecto', () async {
    final gateway = FakePostGateway(
      detailById: {1: detailWithEngagement(id: 1)},
      reactionDelayMs: 80,
    );
    final c = container(gateway);
    addTearDown(c.dispose);

    await c.read(postDetailControllerProvider(1).future);
    final op =
        c.read(postDetailControllerProvider(1).notifier).setLikeReaction();
    await c.read(authControllerProvider.notifier).logout(localOnly: true);
    await op;
    expect(gateway.setReactionCallCount, 1);
  });

  test('logout durante DELETE restaura estado previo', () async {
    final gateway = FakePostGateway(
      detailById: {
        1: detailWithEngagement(
          id: 1,
          myReactionType: 'like',
          reactionsCount: 1,
        ),
      },
      reactionDelayMs: 80,
    );
    final c = container(gateway);
    addTearDown(c.dispose);

    await c.read(postDetailControllerProvider(1).future);
    final op =
        c.read(postDetailControllerProvider(1).notifier).removeLikeReaction();
    await c.read(authControllerProvider.notifier).logout(localOnly: true);
    await op;
    expect(gateway.removeReactionCallCount, 1);
  });

  test('éxito invalida feed', () async {
    final details = {1: detailWithEngagement(id: 1)};
    final gateway = FakePostGateway(
      detailById: details,
      onSetReaction: (id, _) {
        details[id] = detailWithEngagement(
          id: id,
          reactionsCount: 1,
          myReactionType: 'like',
        );
      },
    );
    final c = container(gateway);
    addTearDown(c.dispose);
    c.listen(feedControllerProvider, (_, __) {});

    await c.read(postDetailControllerProvider(1).future);
    await c.read(postDetailControllerProvider(1).notifier).setLikeReaction();
    expect(
      c.read(feedControllerProvider).isLoading ||
          c.read(feedControllerProvider).hasValue,
      isTrue,
    );
  });

  test('contador no negativo al quitar', () async {
    final gateway = FakePostGateway(
      detailById: {
        1: detailWithEngagement(
          id: 1,
          reactionsCount: 0,
          myReactionType: 'like',
        ),
      },
    );
    final c = container(gateway);
    addTearDown(c.dispose);

    await c.read(postDetailControllerProvider(1).future);
    await c.read(postDetailControllerProvider(1).notifier).removeLikeReaction();
    expect(
      c.read(postDetailControllerProvider(1)).value!.engagement.reactionsCount,
      0,
    );
  });
}
