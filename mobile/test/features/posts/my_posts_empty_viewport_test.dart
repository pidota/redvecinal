import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';
import 'package:red_vecinal/features/posts/presentation/my_posts_screen.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

void main() {
  testWidgets('J estado vacío sin overflow en viewport reducido', (
    tester,
  ) async {
    final gateway = FakePostGateway(
      myPostsPage: const PaginatedFeedPosts(
        items: [],
        currentPage: 1,
        lastPage: 1,
      ),
    );

    await tester.binding.setSurfaceSize(const Size(320, 420));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(testAppConfig),
          authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
          postRepositoryProvider.overrideWithValue(gateway),
          authControllerProvider.overrideWith(
            AuthenticatedBootAuthController.new,
          ),
        ],
        child: const MaterialApp(home: MyPostsScreen()),
      ),
    );

    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Sin publicaciones propias'), findsOneWidget);

    await tester.drag(find.byType(ListView), const Offset(0, 120));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
