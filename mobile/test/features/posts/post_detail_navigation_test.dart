import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';
import 'package:red_vecinal/features/posts/presentation/post_detail_invalid_route_screen.dart';

import '../../test_helpers.dart';
import 'post_test_support.dart';

void main() {
  testWidgets('navega desde feed a detalle', (tester) async {
    final fake = FakePostGateway(
      feedPage: PaginatedFeedPosts(
        items: [sampleCommunityPost()],
        currentPage: 1,
        lastPage: 1,
      ),
      detailById: {1: sampleCommunityPostDetail()},
    );
    await openMainShellAuthenticated(tester, postGateway: fake);

    await tester.tap(navBarIcon(Icons.article_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aviso de reunión'));
    await tester.pumpAndSettle();

    expect(find.text('Publicación'), findsOneWidget);
    expect(find.textContaining('reunión del viernes'), findsOneWidget);
  });

  testWidgets('pantalla inválida comunica no disponible', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: PostDetailInvalidRouteScreen()),
    );
    await tester.pumpAndSettle();
    expect(find.text('Publicación no disponible'), findsOneWidget);
  });
}
