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
  Widget wrap(FakePostGateway gateway, {required int postId}) {
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
        home: PostModerationReviewScreen(
          groupId: 5,
          postId: postId,
          groupName: 'Junta Norte',
        ),
      ),
    );
  }

  testWidgets('detalle propuesta nueva con pending_content', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: PostDetail.fromJson(pendingQueuePostJson(id: 1))},
    );

    await tester.pumpWidget(wrap(gateway, postId: 1));
    await tester.pumpAndSettle();

    expect(find.text('Nueva publicación'), findsOneWidget);
    expect(find.text('Propuesta pendiente'), findsOneWidget);
    expect(find.text('Texto enviado a moderación'), findsOneWidget);
    expect(find.text('propuesta.pdf'), findsOneWidget);
    expect(find.text('Versión actualmente publicada'), findsNothing);
    expect(find.text('Aprobar'), findsOneWidget);
    expect(find.text('Rechazar publicación'), findsOneWidget);
  });

  testWidgets('detalle enmienda separa bloques', (tester) async {
    final gateway = FakePostGateway(
      detailById: {2: PostDetail.fromJson(pendingAmendmentPostJson(id: 2))},
    );

    await tester.pumpWidget(wrap(gateway, postId: 2));
    await tester.pumpAndSettle();

    expect(find.text('Modificación pendiente'), findsOneWidget);
    expect(find.text('Modificación propuesta'), findsOneWidget);
    expect(find.text('Título enmienda'), findsOneWidget);
    expect(find.text('Versión actualmente publicada'), findsOneWidget);
    expect(find.text('Título publicado'), findsOneWidget);
    expect(find.text('enmienda.pdf'), findsOneWidget);
    expect(find.text('vivo.pdf'), findsOneWidget);
  });

  testWidgets('403 sin reintentar automático', (tester) async {
    final gateway = FakePostGateway(
      detailFailureById: {1: const ApiForbiddenFailure()},
    );

    await tester.pumpWidget(wrap(gateway, postId: 1));
    await tester.pumpAndSettle();

    expect(find.text('Acceso denegado'), findsOneWidget);
    expect(find.text('Reintentar'), findsNothing);
  });

  testWidgets('propuesta resuelta', (tester) async {
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

    expect(find.text('Propuesta ya resuelta'), findsOneWidget);
    expect(find.text('Volver a la cola'), findsOneWidget);
  });

  testWidgets('viewport 320 px', (tester) async {
    final gateway = FakePostGateway(
      detailById: {
        1: PostDetail.fromJson(
          pendingQueuePostJson(
            id: 1,
            title: 'Título largo ' * 8,
            body: 'Cuerpo extenso ' * 40,
          ),
        ),
      },
    );

    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(wrap(gateway, postId: 1));
    await tester.pumpAndSettle();

    expect(find.text('Revisión de moderación'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('adjuntos requieren acción manual', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: PostDetail.fromJson(pendingQueuePostJson(id: 1))},
    );

    await tester.pumpWidget(wrap(gateway, postId: 1));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.save_alt_outlined), findsWidgets);
    expect(find.text('Guardar temporalmente'), findsNothing);
  });
}
