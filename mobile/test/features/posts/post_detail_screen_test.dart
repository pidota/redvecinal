import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';
import 'package:red_vecinal/features/posts/presentation/post_detail_screen.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

void main() {
  Widget detailApp(FakePostGateway fake, int id) {
    return ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        postRepositoryProvider.overrideWithValue(fake),
        authControllerProvider.overrideWith(
          AuthenticatedBootAuthController.new,
        ),
      ],
      child: MaterialApp(home: PostDetailScreen(postId: id)),
    );
  }

  testWidgets('muestra detalle cargado', (tester) async {
    final fake = FakePostGateway(
      detailById: {2: sampleCommunityPostDetail(id: 2)},
    );

    await tester.pumpWidget(detailApp(fake, 2));
    await tester.pumpAndSettle();

    expect(find.text('Aviso de reunión'), findsOneWidget);
    expect(find.text('Archivos adjuntos'), findsOneWidget);
    expect(find.text('informe.pdf'), findsOneWidget);
  });

  testWidgets('404 muestra publicación no disponible', (tester) async {
    final fake = FakePostGateway(
      detailFailureById: {5: const ApiNotFoundFailure()},
    );

    await tester.pumpWidget(detailApp(fake, 5));
    await tester.pumpAndSettle();

    expect(find.text('Publicación no disponible'), findsOneWidget);
    expect(find.textContaining('junta vecinal'), findsNothing);
  });

  testWidgets('error de red muestra reintentar', (tester) async {
    final fake = FakePostGateway(
      detailFailureById: {1: const ApiNetworkFailure()},
    );

    await tester.pumpWidget(detailApp(fake, 1));
    await tester.pumpAndSettle();

    expect(find.text('No pudimos cargar la publicación'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
