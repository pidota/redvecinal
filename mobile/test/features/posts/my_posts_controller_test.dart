import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/posts/application/my_posts_controller.dart';
import 'package:red_vecinal/features/posts/data/models/feed_post.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

ProviderContainer buildContainer(FakePostGateway gateway) {
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

PaginatedFeedPosts minePage({
  required int page,
  required int last,
  List<int> ids = const [1],
}) {
  return PaginatedFeedPosts(
    items:
        ids
            .map(
              (id) =>
                  FeedPost.fromJson(mineDraftPostJson(id: id, title: 'P$id')),
            )
            .toList(),
    currentPage: page,
    lastPage: last,
  );
}

void main() {
  test('F primera página', () async {
    final gateway = FakePostGateway(
      myPostsPage: minePage(page: 1, last: 1, ids: [7]),
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);

    final page = await c.read(myPostsControllerProvider.future);
    expect(page.items.single.id, 7);
    expect(gateway.listMyPostsCallCount, 1);
  });

  test('G paginación correcta', () async {
    final gateway = FakePostGateway(
      myPostsByPage: {
        1: minePage(page: 1, last: 2, ids: [1, 2]),
        2: minePage(page: 2, last: 2, ids: [2, 3]),
      },
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);

    await c.read(myPostsControllerProvider.future);
    await c.read(myPostsControllerProvider.notifier).loadMore();
    expect(c.read(myPostsControllerProvider).value!.items.map((p) => p.id), [
      1,
      2,
      3,
    ]);
  });

  test('H error segunda página conserva primera', () async {
    final gateway = FakePostGateway(
      myPostsByPage: {
        1: minePage(page: 1, last: 2, ids: [1]),
      },
      myPostsFailure: const ApiNetworkFailure(),
      myPostsFailurePage: 2,
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);

    await c.read(myPostsControllerProvider.future);
    await c.read(myPostsControllerProvider.notifier).loadMore();
    expect(c.read(myPostsControllerProvider).value!.items, hasLength(1));
  });

  test('I pull-to-refresh recarga página 1', () async {
    final gateway = FakePostGateway(
      myPostsByPage: {
        1: minePage(page: 1, last: 1, ids: [1]),
      },
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);

    await c.read(myPostsControllerProvider.future);
    gateway.myPostsByPage = {
      1: minePage(page: 1, last: 1, ids: [9]),
    };
    await c.read(myPostsControllerProvider.notifier).refresh();
    expect(c.read(myPostsControllerProvider).value!.items.single.id, 9);
  });

  test('J doble carga de página dispara una solicitud', () async {
    final gateway = FakePostGateway(
      myPostsDelayMs: 40,
      myPostsByPage: {
        1: minePage(page: 1, last: 3, ids: [1]),
        2: minePage(page: 2, last: 3, ids: [2]),
      },
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);

    await c.read(myPostsControllerProvider.future);
    final before = gateway.listMyPostsCallCount;
    final a = c.read(myPostsControllerProvider.notifier).loadMore();
    final b = c.read(myPostsControllerProvider.notifier).loadMore();
    await Future.wait([a, b]);
    expect(gateway.listMyPostsCallCount - before, 1);
  });

  test('K logout durante solicitud no muestra datos ajenos', () async {
    final gateway = FakePostGateway(myPostsDelayMs: 80);
    final c = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        postRepositoryProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(c.dispose);

    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(),
    );
    final keepAlive = c.listen(myPostsControllerProvider, (_, __) {});
    final op = c.read(myPostsControllerProvider.future);
    await c.read(authControllerProvider.notifier).logout(localOnly: true);
    final page = await op;
    keepAlive.close();
    expect(page.items, isEmpty);
  });

  test('L respuesta tardía no pisa sesión nueva', () async {
    final gateway = FakePostGateway(
      myPostsDelayMs: 80,
      myPostsByPage: {
        1: minePage(page: 1, last: 1, ids: [99]),
      },
    );
    final c = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        postRepositoryProvider.overrideWithValue(gateway),
      ],
    );
    addTearDown(c.dispose);

    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(),
    );
    final keepAlive = c.listen(myPostsControllerProvider, (_, __) {});
    final futureA = c.read(myPostsControllerProvider.future);

    await c.read(authControllerProvider.notifier).logout(localOnly: true);
    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(id: 2, email: 'nuevo@test.com'),
    );

    gateway.myPostsByPage = {
      1: minePage(page: 1, last: 1, ids: [1]),
    };

    await futureA;
    final page = await c.read(myPostsControllerProvider.future);
    keepAlive.close();
    expect(page.items.single.id, 1);
  });

  test('P estado vacío y error inicial', () async {
    final empty = buildContainer(
      FakePostGateway(
        myPostsPage: const PaginatedFeedPosts(
          items: [],
          currentPage: 1,
          lastPage: 1,
        ),
      ),
    );
    addTearDown(empty.dispose);
    expect((await empty.read(myPostsControllerProvider.future)).items, isEmpty);

    final failing = buildContainer(
      FakePostGateway(myPostsFailure: const ApiNetworkFailure()),
    );
    addTearDown(failing.dispose);
    await expectLater(
      failing.read(myPostsControllerProvider.future),
      throwsA(isA<ApiNetworkFailure>()),
    );
  });
}
