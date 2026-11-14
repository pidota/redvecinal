import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/application/create_post_controller.dart';
import 'package:red_vecinal/features/posts/application/draft_recovery_controller.dart';
import 'package:red_vecinal/features/posts/data/models/feed_post.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';
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

  test('dos borradores listados sin adoptar ninguno', () async {
    final gateway = FakePostGateway(
      myPostsPage: PaginatedFeedPosts(
        items: [
          FeedPost.fromJson({
            ...sampleCommunityPostJson(id: 10),
            'status': 'draft',
          }),
          FeedPost.fromJson({
            ...sampleCommunityPostJson(id: 11, title: 'Otro'),
            'status': 'draft',
          }),
        ],
        currentPage: 1,
        lastPage: 1,
      ),
    );
    final c = container(gateway);
    addTearDown(c.dispose);

    await c.read(draftRecoveryControllerProvider.notifier).loadNextPage();
    final browse = c.read(draftRecoveryControllerProvider);
    expect(browse.candidates.length, 2);
    expect(c.read(createPostControllerProvider).confirmedDraftId, isNull);
  });

  test('borrador en página 2 no concluye ausencia en página 1', () async {
    final gateway = FakePostGateway(
      myPostsByPage: {
        1: const PaginatedFeedPosts(items: [], currentPage: 1, lastPage: 2),
        2: PaginatedFeedPosts(
          items: [
            FeedPost.fromJson({
              ...sampleCommunityPostJson(id: 22),
              'status': 'draft',
            }),
          ],
          currentPage: 2,
          lastPage: 2,
        ),
      },
    );
    final c = container(gateway);
    addTearDown(c.dispose);

    await c.read(draftRecoveryControllerProvider.notifier).loadNextPage();
    var browse = c.read(draftRecoveryControllerProvider);
    expect(browse.candidates, isEmpty);
    expect(browse.hasMore, isTrue);
    expect(browse.allPagesLoaded, isFalse);

    await c.read(draftRecoveryControllerProvider.notifier).loadNextPage();
    browse = c.read(draftRecoveryControllerProvider);
    expect(browse.candidates.single.id, 22);
    expect(browse.allPagesLoaded, isTrue);
  });

  test('error de red en mis publicaciones', () async {
    final gateway = FakePostGateway(myPostsFailure: const ApiNetworkFailure());
    final c = container(gateway);
    addTearDown(c.dispose);

    await c.read(draftRecoveryControllerProvider.notifier).loadNextPage();
    final browse = c.read(draftRecoveryControllerProvider);
    expect(browse.failure, isA<ApiNetworkFailure>());
    expect(c.read(createPostControllerProvider).confirmedDraftId, isNull);
  });

  test('logout durante carga descarta resultado', () async {
    final gateway = FakePostGateway(myPostsDelayMs: 80);
    final c = container(gateway);
    addTearDown(c.dispose);

    final op = c.read(draftRecoveryControllerProvider.notifier).loadNextPage();
    await c.read(authControllerProvider.notifier).logout(localOnly: true);
    await op;
    expect(c.read(draftRecoveryControllerProvider).isLoading, isFalse);
  });

  test('respuesta tardía no mezcla páginas', () async {
    final gateway = FakePostGateway(
      myPostsByPage: {
        1: PaginatedFeedPosts(
          items: [
            FeedPost.fromJson({
              ...sampleCommunityPostJson(id: 1),
              'status': 'draft',
            }),
          ],
          currentPage: 1,
          lastPage: 2,
        ),
        2: PaginatedFeedPosts(
          items: [
            FeedPost.fromJson({
              ...sampleCommunityPostJson(id: 2),
              'status': 'draft',
            }),
          ],
          currentPage: 2,
          lastPage: 2,
        ),
      },
      myPostsDelayMs: 50,
    );
    final c = container(gateway);
    addTearDown(c.dispose);

    final first =
        c.read(draftRecoveryControllerProvider.notifier).loadNextPage();
    c.read(draftRecoveryControllerProvider.notifier).reset();
    await first;

    final browse = c.read(draftRecoveryControllerProvider);
    expect(browse.candidates, isEmpty);
  });
}
