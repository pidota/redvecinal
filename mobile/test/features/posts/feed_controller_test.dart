import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/application/feed_controller.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

void main() {
  ProviderContainer buildContainer(FakePostGateway gateway) {
    return ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        postRepositoryProvider.overrideWithValue(gateway),
        authControllerProvider.overrideWith(
          AuthenticatedBootAuthController.new,
        ),
      ],
    );
  }

  PaginatedFeedPosts page({
    required int page,
    required int last,
    List<int> ids = const [1],
  }) {
    return PaginatedFeedPosts(
      items: ids.map((id) => sampleCommunityPost(id: id)).toList(),
      currentPage: page,
      lastPage: last,
    );
  }

  test('carga inicial exitosa', () async {
    final container = buildContainer(FakePostGateway());
    addTearDown(container.dispose);

    final result = await container.read(feedControllerProvider.future);
    expect(result.items, hasLength(1));
  });

  test('estado vacío', () async {
    final gateway = FakePostGateway(
      feedPage: const PaginatedFeedPosts(
        items: [],
        currentPage: 1,
        lastPage: 1,
      ),
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    expect(
      (await container.read(feedControllerProvider.future)).items,
      isEmpty,
    );
  });

  test('error inicial', () async {
    final gateway = FakePostGateway(feedFailure: const ApiNetworkFailure());
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await expectLater(
      container.read(feedControllerProvider.future),
      throwsA(isA<ApiNetworkFailure>()),
    );
  });

  test('error en segunda página conserva primera', () async {
    final gateway = FakePostGateway(
      pagesByNumber: {
        1: page(page: 1, last: 2, ids: [1]),
      },
      feedFailure: const ApiNetworkFailure(),
      feedFailurePage: 2,
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await container.read(feedControllerProvider.future);
    await container.read(feedControllerProvider.notifier).loadMore();

    expect(container.read(feedControllerProvider).value!.items, hasLength(1));
  });

  test('loadMore y duplicados', () async {
    final gateway = FakePostGateway(
      pagesByNumber: {
        1: page(page: 1, last: 2, ids: [1, 2]),
        2: page(page: 2, last: 2, ids: [2, 3]),
      },
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await container.read(feedControllerProvider.future);
    await container.read(feedControllerProvider.notifier).loadMore();
    expect(
      container.read(feedControllerProvider).value!.items.map((p) => p.id),
      [1, 2, 3],
    );
  });

  test('loadMore concurrente dispara una solicitud', () async {
    final gateway = FakePostGateway(
      feedDelayMs: 40,
      pagesByNumber: {
        1: page(page: 1, last: 3, ids: [1]),
        2: page(page: 2, last: 3, ids: [2]),
      },
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await container.read(feedControllerProvider.future);
    final before = gateway.callCount;
    final a = container.read(feedControllerProvider.notifier).loadMore();
    final b = container.read(feedControllerProvider.notifier).loadMore();
    await Future.wait([a, b]);

    expect(gateway.callCount - before, 1);
  });
}
