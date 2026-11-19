import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';
import 'package:red_vecinal/features/posts/presentation/post_moderation_review_screen.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

void main() {
  testWidgets('muestra botón aprobar en revisión válida', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: PostDetail.fromJson(pendingQueuePostJson(id: 1))},
    );

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
        child: const MaterialApp(
          home: PostModerationReviewScreen(groupId: 5, postId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aprobar'), findsOneWidget);
    expect(find.text('Rechazar'), findsNothing);
  });

  testWidgets('oculta botón en revisión resuelta', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail(id: 1)},
    );

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
        child: const MaterialApp(
          home: PostModerationReviewScreen(groupId: 2, postId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aprobar'), findsNothing);
  });

  testWidgets('confirmación cancelada no llama approve', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: PostDetail.fromJson(pendingQueuePostJson(id: 1))},
    );

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
        child: const MaterialApp(
          home: PostModerationReviewScreen(groupId: 5, postId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aprobar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    expect(gateway.approvePostCallCount, 0);
  });

  testWidgets('approve 200 muestra snackbar', (tester) async {
    final approvedJson = Map<String, dynamic>.from(pendingQueuePostJson(id: 1));
    approvedJson['status'] = 'published';
    approvedJson['pending_content'] = null;
    approvedJson['content'] = {
      'revision_id': 99,
      'title': 'Publicado',
      'body': 'OK',
      'body_html': '<p>OK</p>',
    };
    final gateway = FakePostGateway(
      detailById: {1: PostDetail.fromJson(pendingQueuePostJson(id: 1))},
      approvedDetailByPostId: {1: PostDetail.fromJson(approvedJson)},
    );

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
        child: MaterialApp(
          home: const PostModerationReviewScreen(groupId: 5, postId: 1),
          onGenerateRoute:
              (settings) => MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Cola')),
                settings: settings,
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aprobar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aprobar').last);
    await tester.pumpAndSettle();

    expect(find.text('Publicación aprobada correctamente.'), findsOneWidget);
    expect(gateway.approvePostCallCount, 1);
  });

  testWidgets('banner incertidumbre y consulta', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: PostDetail.fromJson(pendingQueuePostJson(id: 1))},
      approveFailureByPostId: {1: const ApiTimeoutFailure()},
    );

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
        child: const MaterialApp(
          home: PostModerationReviewScreen(groupId: 5, postId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aprobar').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aprobar').last);
    await tester.pumpAndSettle();

    expect(find.text('Consultar estado actual'), findsOneWidget);
  });

  testWidgets('viewport 320 px con botón aprobar', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: PostDetail.fromJson(pendingQueuePostJson(id: 1))},
    );

    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

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
        child: const MaterialApp(
          home: PostModerationReviewScreen(groupId: 5, postId: 1),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Aprobar'), findsOneWidget);
  });
}
