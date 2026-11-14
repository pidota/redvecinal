import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/posts/application/feed_controller.dart';
import 'package:red_vecinal/features/posts/application/post_comments_controller.dart';
import 'package:red_vecinal/features/posts/application/post_detail_controller.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_post_comments.dart';
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

  test('carga inicial de comentarios', () async {
    final gateway = FakePostGateway(
      commentsByPostId: {
        2: sampleCommentsPage(items: [sampleComment(id: 10, postId: 2)]),
      },
    );
    final c = container(gateway);
    addTearDown(c.dispose);

    final page = await c.read(postCommentsControllerProvider(2).future);
    expect(page.items.single.id, 10);
    expect(gateway.listCommentsCallCount, 1);
  });

  test('refresh vuelve a cargar', () async {
    final gateway = FakePostGateway();
    final c = container(gateway);
    addTearDown(c.dispose);

    await c.read(postCommentsControllerProvider(1).future);
    await c.read(postCommentsControllerProvider(1).notifier).refresh();
    expect(gateway.listCommentsCallCount, greaterThanOrEqualTo(2));
  });

  test('load more agrega sin duplicar', () async {
    final gateway = FakePostGateway(
      commentPagesByPostId: {
        1: {
          1: PaginatedPostComments(
            items: [sampleComment(id: 1)],
            currentPage: 1,
            lastPage: 2,
          ),
          2: PaginatedPostComments(
            items: [sampleComment(id: 1), sampleComment(id: 2)],
            currentPage: 2,
            lastPage: 2,
          ),
        },
      },
    );
    final c = container(gateway);
    addTearDown(c.dispose);

    await c.read(postCommentsControllerProvider(1).future);
    await c.read(postCommentsControllerProvider(1).notifier).loadMore();
    final state = c.read(postCommentsControllerProvider(1)).value!;
    expect(state.items.map((e) => e.id), [1, 2]);
  });

  test('publicación exitosa agrega comentario', () async {
    final gateway = FakePostGateway();
    final c = container(gateway);
    addTearDown(c.dispose);
    c.listen(postDetailControllerProvider(1), (_, __) {});

    await c.read(postCommentsControllerProvider(1).future);
    final error = await c
        .read(postCommentsControllerProvider(1).notifier)
        .submitComment('  Nuevo mensaje  ');
    expect(error, isNull);
    expect(gateway.createCommentBodies, ['Nuevo mensaje']);
    final page = c.read(postCommentsControllerProvider(1)).value!;
    expect(page.items.any((c) => c.body == 'Nuevo mensaje'), isTrue);
  });

  test('doble envío bloqueado', () async {
    final gateway = FakePostGateway(createCommentDelayMs: 120);
    final c = container(gateway);
    addTearDown(c.dispose);

    await c.read(postCommentsControllerProvider(1).future);

    final first = c
        .read(postCommentsControllerProvider(1).notifier)
        .submitComment('A');
    final second = c
        .read(postCommentsControllerProvider(1).notifier)
        .submitComment('B');
    await first;
    await second;
    expect(gateway.createCommentCallCount, 1);
  });

  test('validación local vacía', () async {
    final gateway = FakePostGateway();
    final c = container(gateway);
    addTearDown(c.dispose);

    await c.read(postCommentsControllerProvider(1).future);
    final failure = await c
        .read(postCommentsControllerProvider(1).notifier)
        .submitComment('   ');
    expect(failure, isA<ApiValidationFailure>());
    expect(gateway.createCommentCallCount, 0);
  });

  test('logout durante GET descarta respuesta tardía', () async {
    final gateway = FakePostGateway(commentsDelayMs: 80);
    final c = container(gateway);
    addTearDown(c.dispose);

    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(),
    );
    final sub = c.listen(postCommentsControllerProvider(1), (_, __) {});
    final future = c.read(postCommentsControllerProvider(1).future);
    await c.read(authControllerProvider.notifier).logout(localOnly: true);
    await future;
    sub.close();
    expect(
      c.read(postCommentsControllerProvider(1)).valueOrNull?.items,
      isEmpty,
    );
  });

  test('logout durante POST no aplica comentario', () async {
    final gateway = FakePostGateway(
      commentsByPostId: {
        1: const PaginatedPostComments(
          items: [],
          currentPage: 1,
          lastPage: 1,
        ),
      },
      createCommentDelayMs: 80,
    );
    final c = container(gateway);
    addTearDown(c.dispose);

    await c.read(postCommentsControllerProvider(1).future);
    final submit = c
        .read(postCommentsControllerProvider(1).notifier)
        .submitComment('Tarde');
    await c.read(authControllerProvider.notifier).logout(localOnly: true);
    await submit;
    final page = c.read(postCommentsControllerProvider(1)).valueOrNull;
    expect(page?.items ?? [], isEmpty);
  });

  test('respuesta tardía tras cambio de usuario', () async {
    final gateway = FakePostGateway(commentsDelayMs: 100);
    final c = container(gateway);
    addTearDown(c.dispose);

    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(),
    );
    final sub = c.listen(postCommentsControllerProvider(1), (_, __) {});
    final futureA = c.read(postCommentsControllerProvider(1).future);
    await c.read(authControllerProvider.notifier).logout(localOnly: true);
    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(id: 2, email: 'otro@test.com'),
    );
    await futureA;
    sub.close();

    final fresh = await c.read(postCommentsControllerProvider(1).future);
    expect(fresh.items, isNotEmpty);
  });

  test('publicación refresca detalle e invalida feed', () async {
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail(id: 1)},
    );
    final c = container(gateway);
    addTearDown(c.dispose);
    c.listen(feedControllerProvider, (_, __) {});
    c.listen(postDetailControllerProvider(1), (_, __) {});

    await c.read(postDetailControllerProvider(1).future);
    await c.read(postCommentsControllerProvider(1).future);
    final callsBefore = gateway.detailCallCount;

    await c
        .read(postCommentsControllerProvider(1).notifier)
        .submitComment('Hola');

    expect(gateway.detailCallCount, greaterThan(callsBefore));
    expect(
      c.read(feedControllerProvider).isLoading ||
          c.read(feedControllerProvider).hasValue,
      isTrue,
    );
  });

  test('POST fallido no cambia conteo de comentarios en lista', () async {
    final gateway = FakePostGateway(
      createCommentFailureByPostId: {1: const ApiForbiddenFailure()},
    );
    final c = container(gateway);
    addTearDown(c.dispose);

    await c.read(postCommentsControllerProvider(1).future);
    final before =
        c.read(postCommentsControllerProvider(1)).value!.items.length;
    final failure = await c
        .read(postCommentsControllerProvider(1).notifier)
        .submitComment('No');
    expect(failure, isA<ApiForbiddenFailure>());
    final after = c.read(postCommentsControllerProvider(1)).value!.items.length;
    expect(after, before);
  });
}
