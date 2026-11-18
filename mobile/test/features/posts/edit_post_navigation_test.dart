import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:red_vecinal/features/posts/data/models/feed_post.dart';
import 'package:red_vecinal/features/posts/data/models/post_category.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';
import 'package:red_vecinal/features/posts/presentation/create_post_screen.dart';
import 'package:red_vecinal/features/posts/presentation/edit_post_screen.dart';
import 'package:red_vecinal/features/posts/presentation/posts_screen.dart';

import '../../test_helpers.dart';
import 'post_test_support.dart';

void main() {
  testWidgets('23 navegación /posts/:postId/edit', (tester) async {
    final gateway = FakePostGateway(
      detailById: {
        55: draftPostDetail(
          id: 55,
          groupId: 2,
          categoryId: 2,
          title: 'Editable',
          body: 'Cuerpo editable',
        ),
      },
      postCategories: const [
        PostCategory(
          id: 2,
          slug: 'aviso-comunitario',
          name: 'Aviso comunitario',
          defaultAudience: 'group',
          sortOrder: 1,
          isSystem: true,
        ),
      ],
    );
    await openMainShellAuthenticated(tester, postGateway: gateway);
    await tester.tap(navBarIcon(Icons.article_outlined));
    await tester.pumpAndSettle();

    final navContext = tester.element(find.byType(PostsScreen));
    GoRouter.of(navContext).push('/posts/55/edit');
    await tester.pumpAndSettle();

    expect(find.byType(EditPostScreen), findsOneWidget);
    expect(find.text('Editar borrador'), findsWidgets);
    expect(find.text('Editable'), findsOneWidget);
  });

  testWidgets('24 /posts/create no regresiona', (tester) async {
    await openMainShellAuthenticated(tester);
    await tester.tap(navBarIcon(Icons.article_outlined));
    await tester.pumpAndSettle();

    final navContext = tester.element(find.byType(PostsScreen));
    GoRouter.of(navContext).push('/posts/create');
    await tester.pumpAndSettle();
    expect(find.byType(CreatePostScreen), findsOneWidget);
  });

  testWidgets('acceso Editar desde Mis publicaciones', (tester) async {
    final gateway = FakePostGateway(
      myPostsPage: PaginatedFeedPosts(
        items: [FeedPost.fromJson(mineDraftPostJson(id: 56, title: 'Mío'))],
        currentPage: 1,
        lastPage: 1,
      ),
      detailById: {
        56: draftPostDetail(
          id: 56,
          groupId: 2,
          categoryId: 2,
          title: 'Mío',
          body: 'Desc',
        ),
      },
      postCategories: const [
        PostCategory(
          id: 2,
          slug: 'aviso-comunitario',
          name: 'Aviso comunitario',
          defaultAudience: 'group',
          sortOrder: 1,
          isSystem: true,
        ),
      ],
    );
    await openMainShellAuthenticated(tester, postGateway: gateway);
    await tester.tap(navBarIcon(Icons.article_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mis publicaciones'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar'));
    await tester.pumpAndSettle();
    expect(find.byType(EditPostScreen), findsOneWidget);
  });

  testWidgets('pending muestra pantalla no editable', (tester) async {
    final gateway = FakePostGateway(
      detailById: {57: pendingPostDetail(id: 57)},
    );
    await openMainShellAuthenticated(tester, postGateway: gateway);
    await tester.tap(navBarIcon(Icons.article_outlined));
    await tester.pumpAndSettle();
    final navContext = tester.element(find.byType(PostsScreen));
    GoRouter.of(navContext).push('/posts/57/edit');
    await tester.pumpAndSettle();
    expect(find.text('No editable'), findsOneWidget);
  });
}
