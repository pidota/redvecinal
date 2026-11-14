import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';
import 'package:red_vecinal/features/posts/presentation/posts_screen.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

void main() {
  testWidgets('pantalla vacía con acción de actualizar', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(testAppConfig),
          authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
          postRepositoryProvider.overrideWithValue(
            FakePostGateway(
              feedPage: const PaginatedFeedPosts(
                items: [],
                currentPage: 1,
                lastPage: 1,
              ),
            ),
          ),
          authControllerProvider.overrideWith(
            AuthenticatedBootAuthController.new,
          ),
        ],
        child: const MaterialApp(home: PostsScreen()),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Sin publicaciones'), findsOneWidget);
    expect(find.text('Actualizar'), findsOneWidget);
  });

  testWidgets('pantalla con publicaciones y cargar más', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(testAppConfig),
          authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
          postRepositoryProvider.overrideWithValue(
            FakePostGateway(
              pagesByNumber: {
                1: PaginatedFeedPosts(
                  items: [sampleCommunityPost()],
                  currentPage: 1,
                  lastPage: 2,
                ),
              },
            ),
          ),
          authControllerProvider.overrideWith(
            AuthenticatedBootAuthController.new,
          ),
        ],
        child: const MaterialApp(home: PostsScreen()),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Aviso de reunión'), findsOneWidget);
    expect(find.text('Cargar más'), findsOneWidget);
  });

  testWidgets('error inicial con reintentar', (tester) async {
    final gateway = FakePostGateway(feedFailure: const ApiNetworkFailure());
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
        child: const MaterialApp(home: PostsScreen()),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('No pudimos cargar el feed'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
