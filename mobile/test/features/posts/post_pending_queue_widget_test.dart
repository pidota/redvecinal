import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/data/models/feed_post.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';
import 'package:red_vecinal/features/posts/presentation/post_pending_queue_screen.dart';
import 'package:red_vecinal/features/posts/presentation/widgets/post_pending_queue_card.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

void main() {
  Widget wrap(FakePostGateway gateway) {
    return ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        postRepositoryProvider.overrideWithValue(gateway),
        authControllerProvider.overrideWith(
          AuthenticatedBootAuthController.new,
        ),
      ],
      child: MaterialApp(
        home: const PostPendingQueueScreen(
          groupId: 5,
          groupName: 'Junta Norte',
        ),
      ),
    );
  }

  testWidgets('nueva publicación desde pending_content', (tester) async {
    final gateway = FakePostGateway(
      pendingPostsByGroupId: {
        5: PaginatedFeedPosts(
          items: [FeedPost.fromJson(pendingQueuePostJson(id: 1))],
          currentPage: 1,
          lastPage: 1,
        ),
      },
    );

    await tester.pumpWidget(wrap(gateway));
    await tester.pumpAndSettle();

    expect(find.text('Nueva publicación'), findsOneWidget);
    expect(find.text('Propuesta pendiente'), findsOneWidget);
    expect(find.text('Vecino autor'), findsOneWidget);
    expect(find.text('Aprobar'), findsNothing);
    expect(find.text('Rechazar'), findsNothing);
  });

  testWidgets('enmienda etiquetada', (tester) async {
    final gateway = FakePostGateway(
      pendingPostsByGroupId: {
        5: PaginatedFeedPosts(
          items: [FeedPost.fromJson(pendingAmendmentPostJson(id: 2))],
          currentPage: 1,
          lastPage: 1,
        ),
      },
    );

    await tester.pumpWidget(wrap(gateway));
    await tester.pumpAndSettle();

    expect(find.text('Modificación pendiente'), findsOneWidget);
    expect(find.text('Título enmienda'), findsOneWidget);
    expect(find.text('Título publicado'), findsNothing);
  });

  testWidgets('403 sin botón reintentar', (tester) async {
    final gateway = FakePostGateway(
      pendingPostsFailureByGroupId: {5: const ApiForbiddenFailure()},
    );

    await tester.pumpWidget(wrap(gateway));
    await tester.pumpAndSettle();

    expect(find.text('Acceso denegado'), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
  });

  testWidgets('banner por omitidos', (tester) async {
    final invalid = Map<String, dynamic>.from(sampleCommunityPostJson());
    invalid.remove('pending_content');
    final gateway = FakePostGateway(
      pendingPostsByGroupId: {
        5: PaginatedFeedPosts(
          items: [
            FeedPost.fromJson(invalid),
            FeedPost.fromJson(pendingQueuePostJson(id: 3)),
          ],
          currentPage: 1,
          lastPage: 1,
        ),
      },
    );

    await tester.pumpWidget(wrap(gateway));
    await tester.pumpAndSettle();

    expect(find.textContaining('no se muestran'), findsOneWidget);
    expect(find.byType(PostPendingQueueCard), findsOneWidget);
  });

  testWidgets('viewport 320 px', (tester) async {
    final gateway = FakePostGateway(
      pendingPostsByGroupId: {
        5: PaginatedFeedPosts(
          items: [
            FeedPost.fromJson(
              pendingQueuePostJson(
                id: 4,
                title: 'Título muy largo ' * 8,
                body: 'Cuerpo extenso ' * 30,
              ),
            ),
          ],
          currentPage: 1,
          lastPage: 1,
        ),
      },
    );

    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(wrap(gateway));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Pendientes · Junta Norte'), findsOneWidget);
    expect(find.byType(PostPendingQueueCard), findsOneWidget);
  });
}
