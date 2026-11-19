import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/neighborhoods/data/neighborhood_repository.dart';
import 'package:red_vecinal/features/posts/data/post_report_outcome_store.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';
import 'package:red_vecinal/features/posts/presentation/post_report_screen.dart';
import 'package:red_vecinal/features/posts/presentation/posts_screen.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import '../neighborhoods/neighborhood_test_support.dart';
import 'post_test_support.dart';

Future<void> openReportForm(
  WidgetTester tester,
  FakePostGateway gateway, {
  InMemoryPostReportOutcomeStore? store,
}) async {
  await pumpRedVecinalApp(
    tester,
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
      tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      authControllerProvider.overrideWith(AuthenticatedBootAuthController.new),
      neighborhoodRepositoryProvider.overrideWithValue(
        FakeNeighborhoodGateway(),
      ),
      postRepositoryProvider.overrideWithValue(gateway),
      if (store != null)
        postReportOutcomeStoreProvider.overrideWithValue(store),
    ],
  );
  await tester.pumpAndSettle();
  await tester.tap(navBarIcon(Icons.article_outlined));
  await tester.pumpAndSettle();
  GoRouter.of(tester.element(find.byType(PostsScreen))).push('/posts/1/report');
  await tester.pumpAndSettle();
}

Future<void> confirmSend(WidgetTester tester) async {
  await tester.tap(find.text('Spam o publicidad no deseada'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Enviar reporte'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Confirmar envío'));
}

void main() {
  testWidgets('envío confirmado muestra snackbar', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail()},
    );
    await openReportForm(tester, gateway);
    await confirmSend(tester);
    await tester.pumpAndSettle();
    expect(find.text('Reporte recibido'), findsOneWidget);
    expect(gateway.reportPostCallCount, 1);
  });

  testWidgets('dos taps en confirmar: un POST', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail()},
      reportDelayMs: 200,
    );
    await openReportForm(tester, gateway);
    await tester.tap(find.text('Spam o publicidad no deseada'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar reporte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar envío'));
    await tester.tap(find.text('Confirmar envío'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(gateway.reportPostCallCount, 1);
  });

  testWidgets('403 muestra falta de autorización', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail()},
      reportFailureByPostId: {1: const ApiForbiddenFailure()},
    );
    await openReportForm(tester, gateway);
    await confirmSend(tester);
    await tester.pumpAndSettle();
    expect(
      find.text('No tienes autorización para reportar esta publicación.'),
      findsOneWidget,
    );
  });

  testWidgets('timeout muestra incertidumbre y bloquea', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail()},
      reportFailureByPostId: {1: const ApiTimeoutFailure()},
    );
    await openReportForm(tester, gateway);
    await confirmSend(tester);
    await tester.pumpAndSettle();
    expect(
      find.textContaining('No pudimos confirmar si tu denuncia fue recibida'),
      findsOneWidget,
    );
    expect(find.textContaining('mismo envío'), findsOneWidget);
    expect(find.textContaining('sin generar otra denuncia'), findsNothing);
    expect(find.text('Comprobar envío'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Enviar reporte'),
    );
    expect(button.onPressed, isNull);
    expect(gateway.reportPostCallCount, 1);
  });

  testWidgets('reapertura tras confirmado permanece bloqueada', (tester) async {
    final store = InMemoryPostReportOutcomeStore();
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail()},
    );
    await openReportForm(tester, gateway, store: store);
    await confirmSend(tester);
    await tester.pumpAndSettle();

    GoRouter.of(
      tester.element(find.byType(PostsScreen)),
    ).push('/posts/1/report');
    await tester.pumpAndSettle();
    expect(find.byType(PostReportScreen), findsOneWidget);
    expect(find.textContaining('Ya enviaste un reporte'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Enviar reporte'),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('navegación durante POST no duplica', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail()},
      reportDelayMs: 200,
    );
    await openReportForm(tester, gateway);
    await tester.tap(find.text('Spam o publicidad no deseada'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar reporte'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar envío'));
    await tester.pump();
    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(gateway.reportPostCallCount, 1);
  });

  testWidgets('render 320 px con envío', (tester) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail()},
    );
    await openReportForm(tester, gateway);
    expect(tester.takeException(), isNull);
  });
}
