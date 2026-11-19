import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/posts/application/post_pending_queue_controller.dart';
import 'package:red_vecinal/features/posts/data/models/feed_post.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

const _groupId = 5;

ProviderContainer queueContainer(FakePostGateway gateway) {
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

PaginatedFeedPosts pendingPage({
  required int page,
  required int last,
  List<Map<String, dynamic>> itemsJson = const [],
}) {
  final items =
      itemsJson.isEmpty
          ? [FeedPost.fromJson(pendingQueuePostJson(id: 10))]
          : itemsJson.map(FeedPost.fromJson).toList();
  return PaginatedFeedPosts(items: items, currentPage: page, lastPage: last);
}

void main() {
  test('primera carga exitosa', () async {
    final gateway = FakePostGateway(
      pendingPostsByGroupId: {_groupId: pendingPage(page: 1, last: 1)},
    );
    final c = queueContainer(gateway);
    addTearDown(c.dispose);

    final queue = await c.read(
      postPendingQueueControllerProvider(_groupId).future,
    );
    expect(queue.reviewableItems, hasLength(1));
    expect(queue.reviewableItems.first.pendingTitle, 'Propuesta pendiente');
    expect(gateway.listPendingPostsCallCount, 1);
  });

  test('cola vacía', () async {
    final gateway = FakePostGateway(
      pendingPostsByGroupId: {
        _groupId: const PaginatedFeedPosts(
          items: [],
          currentPage: 1,
          lastPage: 1,
        ),
      },
    );
    final c = queueContainer(gateway);
    addTearDown(c.dispose);

    final queue = await c.read(
      postPendingQueueControllerProvider(_groupId).future,
    );
    expect(queue.isTrulyEmpty, isTrue);
  });

  test('paginación y fin', () async {
    final gateway = FakePostGateway(
      pendingPostsPagesByGroupId: {
        _groupId: {
          1: pendingPage(
            page: 1,
            last: 2,
            itemsJson: [pendingQueuePostJson(id: 1)],
          ),
          2: pendingPage(
            page: 2,
            last: 2,
            itemsJson: [pendingQueuePostJson(id: 2, title: 'Segunda')],
          ),
        },
      },
    );
    final c = queueContainer(gateway);
    addTearDown(c.dispose);

    await c.read(postPendingQueueControllerProvider(_groupId).future);
    await c
        .read(postPendingQueueControllerProvider(_groupId).notifier)
        .loadMore();
    final queue = c.read(postPendingQueueControllerProvider(_groupId)).value!;
    expect(queue.reviewableItems, hasLength(2));
    expect(queue.hasMore, isFalse);
  });

  test('refresh reemplaza datos', () async {
    final gateway = FakePostGateway(
      pendingPostsByGroupId: {_groupId: pendingPage(page: 1, last: 1)},
    );
    final c = queueContainer(gateway);
    addTearDown(c.dispose);

    await c.read(postPendingQueueControllerProvider(_groupId).future);
    gateway.pendingPostsByGroupId = {
      _groupId: pendingPage(
        page: 1,
        last: 1,
        itemsJson: [pendingQueuePostJson(id: 99, title: 'Actualizado')],
      ),
    };
    await c
        .read(postPendingQueueControllerProvider(_groupId).notifier)
        .refresh();
    expect(
      c
          .read(postPendingQueueControllerProvider(_groupId))
          .value!
          .reviewableItems
          .first
          .pendingTitle,
      'Actualizado',
    );
  });

  test('enmienda identificada', () async {
    final gateway = FakePostGateway(
      pendingPostsByGroupId: {
        _groupId: pendingPage(
          page: 1,
          last: 1,
          itemsJson: [pendingAmendmentPostJson(id: 40)],
        ),
      },
    );
    final c = queueContainer(gateway);
    addTearDown(c.dispose);

    final review =
        (await c.read(
          postPendingQueueControllerProvider(_groupId).future,
        )).reviewableItems.single;
    expect(review.isAmendment, isTrue);
    expect(review.pendingTitle, 'Título enmienda');
    expect(review.publishedTitle, 'Título publicado');
  });

  test('elemento sin pending_content omitido', () async {
    final invalid = Map<String, dynamic>.from(sampleCommunityPostJson());
    invalid.remove('pending_content');
    invalid['status'] = 'pending';

    final gateway = FakePostGateway(
      pendingPostsByGroupId: {
        _groupId: pendingPage(
          page: 1,
          last: 1,
          itemsJson: [invalid, pendingQueuePostJson(id: 2)],
        ),
      },
    );
    final c = queueContainer(gateway);
    addTearDown(c.dispose);

    final queue = await c.read(
      postPendingQueueControllerProvider(_groupId).future,
    );
    expect(queue.reviewableItems, hasLength(1));
    expect(queue.skippedItemCount, 1);
    expect(queue.hasOnlySkippedItems, isFalse);
  });

  test('solo elementos inválidos', () async {
    final invalid = Map<String, dynamic>.from(sampleCommunityPostJson());
    invalid.remove('pending_content');
    final gateway = FakePostGateway(
      pendingPostsByGroupId: {
        _groupId: pendingPage(page: 1, last: 1, itemsJson: [invalid]),
      },
    );
    final c = queueContainer(gateway);
    addTearDown(c.dispose);

    final queue = await c.read(
      postPendingQueueControllerProvider(_groupId).future,
    );
    expect(queue.hasOnlySkippedItems, isTrue);
    expect(queue.reviewableItems, isEmpty);
  });

  test('403 error', () async {
    final gateway = FakePostGateway(
      pendingPostsFailureByGroupId: {_groupId: const ApiForbiddenFailure()},
    );
    final c = queueContainer(gateway);
    addTearDown(c.dispose);

    await expectLater(
      c.read(postPendingQueueControllerProvider(_groupId).future),
      throwsA(isA<ApiForbiddenFailure>()),
    );
    expect(
      c.read(postPendingQueueControllerProvider(_groupId)).hasError,
      isTrue,
    );
    expect(
      c.read(postPendingQueueControllerProvider(_groupId)).error,
      isA<ApiForbiddenFailure>(),
    );
  });

  test('404 error', () async {
    final gateway = FakePostGateway(
      pendingPostsFailureByGroupId: {_groupId: const ApiNotFoundFailure()},
    );
    final c = queueContainer(gateway);
    addTearDown(c.dispose);

    await expectLater(
      c.read(postPendingQueueControllerProvider(_groupId).future),
      throwsA(isA<ApiNotFoundFailure>()),
    );
  });

  test('timeout en refresh', () async {
    final gateway = FakePostGateway(
      pendingPostsByGroupId: {_groupId: pendingPage(page: 1, last: 1)},
    );
    final c = queueContainer(gateway);
    addTearDown(c.dispose);

    await c.read(postPendingQueueControllerProvider(_groupId).future);
    gateway.pendingPostsFailureByGroupId = {
      _groupId: const ApiTimeoutFailure(),
    };
    await c
        .read(postPendingQueueControllerProvider(_groupId).notifier)
        .refresh();
    expect(
      c.read(postPendingQueueControllerProvider(_groupId)).error,
      isA<ApiTimeoutFailure>(),
    );
  });

  test('500 error', () async {
    final gateway = FakePostGateway(
      pendingPostsFailureByGroupId: {_groupId: const ApiServerFailure()},
    );
    final c = queueContainer(gateway);
    addTearDown(c.dispose);

    await expectLater(
      c.read(postPendingQueueControllerProvider(_groupId).future),
      throwsA(isA<ApiServerFailure>()),
    );
  });

  test('logout durante carga', () async {
    final gateway = FakePostGateway(pendingPostsDelayMs: 80);
    gateway.pendingPostsByGroupId = {_groupId: pendingPage(page: 1, last: 1)};
    final c = queueContainer(gateway);
    final keepAlive = c.listen(
      postPendingQueueControllerProvider(_groupId),
      (_, __) {},
    );
    addTearDown(() {
      keepAlive.close();
      c.dispose();
    });

    final future = c.read(postPendingQueueControllerProvider(_groupId).future);
    await c.read(authControllerProvider.notifier).logout(localOnly: true);
    final queue = await future;
    expect(queue.isTrulyEmpty, isTrue);
  });

  test('cambio de groupId aísla providers', () async {
    final gateway = FakePostGateway(
      pendingPostsByGroupId: {
        5: pendingPage(
          page: 1,
          last: 1,
          itemsJson: [pendingQueuePostJson(id: 1, title: 'G5')],
        ),
        9: pendingPage(
          page: 1,
          last: 1,
          itemsJson: [pendingQueuePostJson(id: 2, title: 'G9')],
        ),
      },
    );
    final c = queueContainer(gateway);
    addTearDown(c.dispose);

    final q5 = await c.read(postPendingQueueControllerProvider(5).future);
    final q9 = await c.read(postPendingQueueControllerProvider(9).future);
    expect(q5.reviewableItems.first.pendingTitle, 'G5');
    expect(q9.reviewableItems.first.pendingTitle, 'G9');
  });

  test('respuesta obsoleta tras refresh', () async {
    final gateway = FakePostGateway(pendingPostsDelayMs: 80);
    gateway.pendingPostsByGroupId = {
      _groupId: pendingPage(
        page: 1,
        last: 1,
        itemsJson: [pendingQueuePostJson(id: 1, title: 'Tardío')],
      ),
    };
    final c = queueContainer(gateway);
    final keepAlive = c.listen(
      postPendingQueueControllerProvider(_groupId),
      (_, __) {},
    );
    addTearDown(() {
      keepAlive.close();
      c.dispose();
    });

    await c.read(postPendingQueueControllerProvider(_groupId).future);

    gateway.pendingPostsByGroupId = {
      _groupId: pendingPage(
        page: 1,
        last: 1,
        itemsJson: [pendingQueuePostJson(id: 2, title: 'Actualizado')],
      ),
    };
    gateway.pendingPostsDelayMs = 0;

    final slowRefresh =
        c.read(postPendingQueueControllerProvider(_groupId).notifier).refresh();
    final generationBefore = c.read(
      postPendingQueueControllerProvider(_groupId).notifier,
    );
    await c
        .read(postPendingQueueControllerProvider(_groupId).notifier)
        .refresh();
    await slowRefresh;

    final title =
        c
            .read(postPendingQueueControllerProvider(_groupId))
            .value
            ?.reviewableItems
            .first
            .pendingTitle;
    expect(title, 'Actualizado');
    expect(generationBefore, isNotNull);
  });
}
