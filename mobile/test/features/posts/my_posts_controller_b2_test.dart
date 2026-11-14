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

import '../auth/auth_test_support.dart';
import 'my_posts_controller_test.dart';
import 'post_test_support.dart';

Future<void> waitForMyPostsSettled(ProviderContainer c) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    final async = c.read(myPostsControllerProvider);
    if (async.hasError) {
      return;
    }
    if (async.hasValue && !async.isLoading) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail(
    'myPostsController no terminó de cargar: ${c.read(myPostsControllerProvider)}',
  );
}

void main() {
  ProviderContainer sessionContainer(FakePostGateway gateway) {
    return ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        postRepositoryProvider.overrideWithValue(gateway),
      ],
    );
  }

  test('F logout durante loadMore no conserva página extendida', () async {
    final gateway = FakePostGateway(
      myPostsDelayMs: 80,
      myPostsByPage: {
        1: minePage(page: 1, last: 2, ids: [1]),
        2: minePage(page: 2, last: 2, ids: [2]),
      },
    );
    final c = sessionContainer(gateway);
    addTearDown(c.dispose);

    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(),
    );
    final sub = c.listen(myPostsControllerProvider, (_, __) {});
    await c.read(myPostsControllerProvider.future);

    final loadOp = c.read(myPostsControllerProvider.notifier).loadMore();
    await c.read(authControllerProvider.notifier).logout(localOnly: true);
    await loadOp;

    final page = await c.read(myPostsControllerProvider.future);
    sub.close();
    expect(page.items, isEmpty);
  });

  test('G refresh durante loadMore descarta append', () async {
    final gateway = FakePostGateway(
      myPostsDelayMs: 80,
      myPostsByPage: {
        1: minePage(page: 1, last: 2, ids: [1]),
        2: minePage(page: 2, last: 2, ids: [2, 3]),
      },
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);
    final keepAlive = c.listen(myPostsControllerProvider, (_, __) {});

    await c.read(myPostsControllerProvider.future);
    final loadOp = c.read(myPostsControllerProvider.notifier).loadMore();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await c.read(myPostsControllerProvider.notifier).refresh();
    await loadOp;

    final page = c.read(myPostsControllerProvider).requireValue;
    expect(page.items.map((p) => p.id), [1]);
    expect(page.items.any((p) => p.id == 3), isFalse);
    expect(gateway.listMyPostsCallCount, greaterThanOrEqualTo(2));
    keepAlive.close();
  });

  test('H loadMore tardío tras refresh no reinyecta ítems antiguos', () async {
    final gateway = FakePostGateway(
      myPostsDelayMs: 100,
      myPostsByPage: {
        1: minePage(page: 1, last: 2, ids: [10]),
        2: PaginatedFeedPosts(
          items: [
            FeedPost.fromJson(mineDraftPostJson(id: 99, title: 'Fantasma')),
          ],
          currentPage: 2,
          lastPage: 2,
        ),
      },
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);
    final keepAlive = c.listen(myPostsControllerProvider, (_, __) {});

    await c.read(myPostsControllerProvider.future);
    gateway.myPostsByPage = {
      1: minePage(page: 1, last: 1, ids: [11]),
    };
    final loadOp = c.read(myPostsControllerProvider.notifier).loadMore();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await c.read(myPostsControllerProvider.notifier).refresh();
    await loadOp;

    final page = c.read(myPostsControllerProvider).requireValue;
    expect(page.items.map((p) => p.id), [11]);
    expect(page.items.any((p) => p.id == 99), isFalse);
    keepAlive.close();
  });

  test('I 401 en refresh no deja datos previos en estado data', () async {
    final gateway = FakePostGateway(
      myPostsPage: minePage(page: 1, last: 1, ids: [5]),
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);

    await c.read(myPostsControllerProvider.future);
    gateway.myPostsFailure = const ApiSessionExpiredFailure();
    gateway.myPostsFailurePage = 1;

    await c.read(myPostsControllerProvider.notifier).refresh();
    await waitForMyPostsSettled(c);

    final async = c.read(myPostsControllerProvider);
    expect(async.hasError, isTrue);
    expect(async.error, isA<ApiSessionExpiredFailure>());
    expect(async.isLoading, isFalse);
  });
}
