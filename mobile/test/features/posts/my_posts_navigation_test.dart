import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:red_vecinal/features/posts/data/models/feed_post.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';
import 'package:red_vecinal/features/posts/presentation/my_posts_screen.dart';
import 'package:red_vecinal/features/posts/presentation/post_detail_screen.dart';
import 'package:red_vecinal/features/posts/presentation/posts_screen.dart';

import '../../test_helpers.dart';
import 'post_test_support.dart';

void main() {
  testWidgets('N /posts/mine no colisiona con /posts/:postId', (tester) async {
    final gateway = FakePostGateway(
      detailById: {42: sampleCommunityPostDetail(id: 42)},
    );
    await openMainShellAuthenticated(tester, postGateway: gateway);
    await tester.tap(navBarIcon(Icons.article_outlined));
    await tester.pumpAndSettle();

    final navContext = tester.element(find.byType(PostsScreen));
    GoRouter.of(navContext).push('/posts/mine');
    await tester.pumpAndSettle();
    expect(find.byType(MyPostsScreen), findsOneWidget);

    GoRouter.of(navContext).push('/posts/42');
    await tester.pumpAndSettle();
    expect(find.byType(PostDetailScreen), findsOneWidget);
    expect(find.byType(MyPostsScreen), findsNothing);
  });

  testWidgets('M navega a Mis publicaciones', (tester) async {
    final gateway = FakePostGateway(
      myPostsPage: PaginatedFeedPosts(
        items: [FeedPost.fromJson(mineDraftPostJson(title: 'Mi borrador'))],
        currentPage: 1,
        lastPage: 1,
      ),
    );
    await openMainShellAuthenticated(tester, postGateway: gateway);
    await tester.tap(navBarIcon(Icons.article_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mis publicaciones'));
    await tester.pumpAndSettle();

    expect(find.byType(MyPostsScreen), findsOneWidget);
    expect(find.text('Mi borrador'), findsOneWidget);
  });

  testWidgets('O detalle de borrador propio muestra estado y contenido', (
    tester,
  ) async {
    final gateway = FakePostGateway(
      myPostsPage: PaginatedFeedPosts(
        items: [FeedPost.fromJson(mineDraftPostJson(title: 'Borrador X'))],
        currentPage: 1,
        lastPage: 1,
      ),
      detailById: {
        50: draftPostDetail(
          id: 50,
          groupId: 2,
          categoryId: 2,
          title: 'Borrador X',
          body: 'Contenido borrador',
        ),
      },
    );
    await openMainShellAuthenticated(tester, postGateway: gateway);
    await tester.tap(navBarIcon(Icons.article_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mis publicaciones'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Borrador X'));
    await tester.pumpAndSettle();

    expect(find.text('Borrador'), findsWidgets);
    expect(find.textContaining('Contenido borrador'), findsOneWidget);
    expect(find.text('Publicada'), findsNothing);
  });
}
