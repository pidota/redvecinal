import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';
import 'package:red_vecinal/features/posts/presentation/post_moderation_review_screen.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

void main() {
  testWidgets('muestra botones aprobar y rechazar', (tester) async {
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

    expect(find.text('Rechazar publicación'), findsOneWidget);
    expect(find.text('Aprobar'), findsOneWidget);
  });

  testWidgets('motivo obligatorio en diálogo', (tester) async {
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

    await tester.tap(find.text('Rechazar publicación'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar rechazo'));
    await tester.pumpAndSettle();

    expect(find.text('El motivo de rechazo es obligatorio.'), findsOneWidget);
    expect(gateway.rejectPostCallCount, 0);
  });

  testWidgets('reject 200 navega con mensaje', (tester) async {
    final rejectedJson = Map<String, dynamic>.from(pendingQueuePostJson(id: 1));
    rejectedJson['status'] = 'rejected';
    rejectedJson['pending_content'] = null;
    final gateway = FakePostGateway(
      detailById: {1: PostDetail.fromJson(pendingQueuePostJson(id: 1))},
      rejectedDetailByPostId: {1: PostDetail.fromJson(rejectedJson)},
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

    await tester.tap(find.text('Rechazar publicación'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'No cumple normas.');
    await tester.tap(find.text('Confirmar rechazo'));
    await tester.pumpAndSettle();

    expect(find.text('Publicación rechazada correctamente.'), findsOneWidget);
    expect(gateway.rejectPostCallCount, 1);
  });

  testWidgets('viewport 320 px con dos botones', (tester) async {
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

    expect(find.text('Rechazar publicación'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
