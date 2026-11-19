import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/neighborhoods/presentation/neighborhood_detail_screen.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';
import 'package:red_vecinal/features/posts/presentation/post_pending_queue_screen.dart';

import '../../test_helpers.dart';
import '../neighborhoods/neighborhood_test_support.dart';
import 'post_test_support.dart';

Future<void> openGroupDetail(
  WidgetTester tester, {
  required FakeNeighborhoodGateway neighborhoodGateway,
  required FakePostGateway postGateway,
  String location = '/neighborhoods/1',
}) async {
  await openMainShellAuthenticated(
    tester,
    neighborhoodGateway: neighborhoodGateway,
    postGateway: postGateway,
  );
  await tester.tap(navBarIcon(Icons.holiday_village_outlined));
  await tester.pumpAndSettle();
  final context = tester.element(find.text('Mis juntas'));
  GoRouter.of(context).push(location);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('navegación desde detalle con groupName', (tester) async {
    final neighborhood = FakeNeighborhoodGateway(
      groups: [sampleNeighborhoodGroup(id: 1, name: 'Junta Centro')],
    );
    final posts = FakePostGateway(
      pendingPostsByGroupId: {
        1: const PaginatedFeedPosts(items: [], currentPage: 1, lastPage: 1),
      },
    );

    await openGroupDetail(
      tester,
      neighborhoodGateway: neighborhood,
      postGateway: posts,
    );

    expect(find.text('Moderar publicaciones'), findsOneWidget);
    await tester.tap(find.text('Moderar publicaciones'));
    await tester.pumpAndSettle();

    expect(find.byType(PostPendingQueueScreen), findsOneWidget);
    expect(find.text('Pendientes · Junta Centro'), findsOneWidget);
    expect(posts.listPendingPostsCallCount, 2);
  });

  testWidgets('403 en sondeo oculta entrada', (tester) async {
    final neighborhood = FakeNeighborhoodGateway(
      groups: [sampleNeighborhoodGroup()],
    );
    final posts = FakePostGateway(
      pendingPostsFailureByGroupId: {1: const ApiForbiddenFailure()},
    );

    await openGroupDetail(
      tester,
      neighborhoodGateway: neighborhood,
      postGateway: posts,
    );

    expect(find.byType(NeighborhoodDetailScreen), findsOneWidget);
    expect(find.text('Moderar publicaciones'), findsNothing);
    expect(posts.listPendingPostsCallCount, 1);
  });

  testWidgets('junta suspendida sin entrada', (tester) async {
    final neighborhood = FakeNeighborhoodGateway(
      groups: [sampleNeighborhoodGroup(status: 'suspended')],
    );
    final posts = FakePostGateway(
      pendingPostsByGroupId: {
        1: const PaginatedFeedPosts(items: [], currentPage: 1, lastPage: 1),
      },
    );

    await openGroupDetail(
      tester,
      neighborhoodGateway: neighborhood,
      postGateway: posts,
    );

    expect(find.text('Suspendida'), findsOneWidget);
    expect(find.text('Moderar publicaciones'), findsNothing);
    expect(posts.listPendingPostsCallCount, 0);
  });

  testWidgets('render 320 px sin overflow', (tester) async {
    final neighborhood = FakeNeighborhoodGateway(
      groups: [sampleNeighborhoodGroup()],
    );
    final posts = FakePostGateway(
      pendingPostsByGroupId: {
        1: const PaginatedFeedPosts(items: [], currentPage: 1, lastPage: 1),
      },
    );

    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;

    await openGroupDetail(
      tester,
      neighborhoodGateway: neighborhood,
      postGateway: posts,
    );

    expect(find.text('Moderar publicaciones'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('regreso desde cola mantiene detalle', (tester) async {
    final neighborhood = FakeNeighborhoodGateway(
      groups: [sampleNeighborhoodGroup()],
    );
    final posts = FakePostGateway(
      pendingPostsByGroupId: {
        1: const PaginatedFeedPosts(items: [], currentPage: 1, lastPage: 1),
      },
    );

    await openGroupDetail(
      tester,
      neighborhoodGateway: neighborhood,
      postGateway: posts,
    );
    await tester.tap(find.text('Moderar publicaciones'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(NeighborhoodDetailScreen), findsOneWidget);
    expect(find.text('Detalle de junta'), findsOneWidget);
  });
}
