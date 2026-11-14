import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/posts/application/feed_controller.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

ProviderContainer postsSessionContainer(FakePostGateway gateway) {
  return ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(testAppConfig),
      authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
      tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      postRepositoryProvider.overrideWithValue(gateway),
    ],
  );
}

void main() {
  test('logout vacía el feed', () async {
    final gateway = FakePostGateway();
    final container = postsSessionContainer(gateway);
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(),
    );
    await container.read(feedControllerProvider.future);

    await container
        .read(authControllerProvider.notifier)
        .logout(localOnly: true);

    final feed = await container.read(feedControllerProvider.future);
    expect(feed.items, isEmpty);
  });

  test('respuesta tardía no pisa sesión nueva', () async {
    final gateway = FakePostGateway(
      feedDelayMs: 80,
      pagesByNumber: {
        1: PaginatedFeedPosts(
          items: [sampleCommunityPost(id: 99)],
          currentPage: 1,
          lastPage: 1,
        ),
      },
    );
    final container = postsSessionContainer(gateway);
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(),
    );
    final keepAlive = container.listen(feedControllerProvider, (_, __) {});
    final futureA = container.read(feedControllerProvider.future);

    await container
        .read(authControllerProvider.notifier)
        .logout(localOnly: true);
    container.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(id: 2, email: 'b@test.com'),
    );

    gateway.pagesByNumber = {
      1: PaginatedFeedPosts(
        items: [sampleCommunityPost(id: 1)],
        currentPage: 1,
        lastPage: 1,
      ),
    };

    await futureA;
    final feed = await container.read(feedControllerProvider.future);
    keepAlive.close();
    expect(feed.items.map((p) => p.id), [1]);
  });
}
