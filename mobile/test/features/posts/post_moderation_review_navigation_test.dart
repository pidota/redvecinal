import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:red_vecinal/features/posts/data/models/feed_post.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';
import 'package:red_vecinal/features/posts/presentation/post_moderation_review_screen.dart';
import 'package:red_vecinal/features/posts/presentation/post_pending_queue_screen.dart';
import 'package:red_vecinal/features/posts/presentation/posts_screen.dart';

import '../../test_helpers.dart';
import 'post_test_support.dart';

void main() {
  testWidgets('navegación cola → detalle y regreso', (tester) async {
    final feedJson = Map<String, dynamic>.from(
      pendingQueuePostJson(id: 11, title: 'Desde cola'),
    );
    feedJson['neighborhood_group'] = {
      'id': 7,
      'name': 'Junta Sur',
      'slug': 'junta-sur',
    };
    final detailJson = Map<String, dynamic>.from(feedJson);

    final gateway = FakePostGateway(
      pendingPostsByGroupId: {
        7: PaginatedFeedPosts(
          items: [FeedPost.fromJson(feedJson)],
          currentPage: 1,
          lastPage: 1,
        ),
      },
      detailById: {11: PostDetail.fromJson(detailJson)},
    );

    await openMainShellAuthenticated(tester, postGateway: gateway);
    await tester.tap(navBarIcon(Icons.article_outlined));
    await tester.pumpAndSettle();

    final navContext = tester.element(find.byType(PostsScreen));
    GoRouter.of(
      navContext,
    ).push('/neighborhoods/7/posts/pending?groupName=Junta%20Sur');
    await tester.pumpAndSettle();

    expect(find.byType(PostPendingQueueScreen), findsOneWidget);
    await tester.tap(find.text('Desde cola'));
    await tester.pumpAndSettle();

    expect(find.byType(PostModerationReviewScreen), findsOneWidget);
    expect(find.text('Desde cola'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(PostPendingQueueScreen), findsOneWidget);
  });

  testWidgets('ruta directa /posts/pending/:postId', (tester) async {
    final gateway = FakePostGateway(
      detailById: {
        55: PostDetail.fromJson(pendingQueuePostJson(id: 55, title: 'Directo')),
      },
    );

    await openMainShellAuthenticated(tester, postGateway: gateway);
    await tester.tap(navBarIcon(Icons.article_outlined));
    await tester.pumpAndSettle();

    final navContext = tester.element(find.byType(PostsScreen));
    GoRouter.of(
      navContext,
    ).push('/neighborhoods/5/posts/pending/55?groupName=Junta%20Norte');
    await tester.pumpAndSettle();

    expect(find.byType(PostModerationReviewScreen), findsOneWidget);
    expect(find.text('Directo'), findsOneWidget);
    expect(find.text('Junta Norte'), findsOneWidget);
  });
}
