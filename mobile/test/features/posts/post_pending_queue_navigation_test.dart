import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:red_vecinal/features/posts/data/models/feed_post.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';
import 'package:red_vecinal/features/posts/presentation/post_pending_queue_screen.dart';
import 'package:red_vecinal/features/posts/presentation/posts_screen.dart';

import '../../test_helpers.dart';
import 'post_test_support.dart';

void main() {
  testWidgets('ruta /neighborhoods/:groupId/posts/pending', (tester) async {
    final gateway = FakePostGateway(
      pendingPostsByGroupId: {
        7: PaginatedFeedPosts(
          items: [FeedPost.fromJson(pendingQueuePostJson(id: 1))],
          currentPage: 1,
          lastPage: 1,
        ),
      },
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
    expect(find.text('Pendientes · Junta Sur'), findsOneWidget);
    expect(find.text('Nueva publicación'), findsOneWidget);
  });
}
