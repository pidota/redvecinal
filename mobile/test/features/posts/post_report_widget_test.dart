import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/posts/data/post_report_validation.dart';
import 'package:red_vecinal/features/posts/presentation/post_detail_screen.dart';
import 'package:red_vecinal/features/posts/presentation/post_report_screen.dart';
import 'package:red_vecinal/features/posts/presentation/posts_screen.dart';

import '../../test_helpers.dart';
import 'post_test_support.dart';

Future<void> openPostDetail(
  WidgetTester tester,
  FakePostGateway gateway, {
  int postId = 1,
}) async {
  await openMainShellAuthenticated(tester, postGateway: gateway);
  await tester.tap(navBarIcon(Icons.article_outlined));
  await tester.pumpAndSettle();
  final context = tester.element(find.byType(PostsScreen));
  GoRouter.of(context).push('/posts/$postId');
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('acción visible en publicación publicada', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail()},
    );
    await openPostDetail(tester, gateway);
    expect(find.bySemanticsLabel('Reportar publicación'), findsOneWidget);
  });

  for (final status in ['draft', 'pending', 'rejected', 'hidden', 'archived']) {
    testWidgets('acción oculta en $status', (tester) async {
      final gateway = FakePostGateway(
        detailById: {1: postDetailWithStatus(status)},
      );
      await openPostDetail(tester, gateway);
      expect(find.bySemanticsLabel('Reportar publicación'), findsNothing);
    });
  }

  testWidgets('navegación a /posts/:id/report', (tester) async {
    final gateway = FakePostGateway(
      detailById: {9: sampleCommunityPostDetail(id: 9)},
    );
    await openPostDetail(tester, gateway, postId: 9);
    await tester.tap(find.bySemanticsLabel('Reportar publicación'));
    await tester.pumpAndSettle();
    expect(find.byType(PostReportScreen), findsOneWidget);
    expect(find.text('Reportar publicación'), findsWidgets);
  });

  testWidgets('postId en ruta del formulario', (tester) async {
    final gateway = FakePostGateway(
      detailById: {42: sampleCommunityPostDetail(id: 42)},
    );
    await openPostDetail(tester, gateway, postId: 42);
    await tester.tap(find.bySemanticsLabel('Reportar publicación'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<PostReportScreen>(find.byType(PostReportScreen)).postId,
      42,
    );
  });

  testWidgets('motivo spam seleccionable', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail()},
    );
    await openPostDetail(tester, gateway);
    await tester.tap(find.bySemanticsLabel('Reportar publicación'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spam o publicidad no deseada'));
    await tester.pumpAndSettle();
    final radio = tester.widget<RadioListTile<String>>(
      find.byType(RadioListTile<String>).first,
    );
    expect(radio.groupValue, 'spam');
  });

  testWidgets('motivo inappropriate seleccionable', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail()},
    );
    await openPostDetail(tester, gateway);
    await tester.tap(find.bySemanticsLabel('Reportar publicación'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Contenido inapropiado'));
    await tester.pumpAndSettle();
    final radio = tester.widget<RadioListTile<String>>(
      find.byWidgetPredicate(
        (w) => w is RadioListTile<String> && w.value == 'inappropriate',
      ),
    );
    expect(radio.groupValue, 'inappropriate');
  });

  testWidgets('detalles opcionales', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail()},
    );
    await openPostDetail(tester, gateway);
    await tester.tap(find.bySemanticsLabel('Reportar publicación'));
    await tester.pumpAndSettle();
    expect(find.text('Detalles (opcional)'), findsOneWidget);
    await tester.tap(find.text('Enviar reporte'));
    await tester.pumpAndSettle();
    expect(find.text('El motivo del reporte es obligatorio.'), findsOneWidget);
  });

  testWidgets('contador de caracteres', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail()},
    );
    await openPostDetail(tester, gateway);
    await tester.tap(find.bySemanticsLabel('Reportar publicación'));
    await tester.pumpAndSettle();
    expect(find.text('0/$postReportDetailsMaxLength'), findsOneWidget);
  });

  testWidgets('validación de motivo', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail()},
    );
    await openPostDetail(tester, gateway);
    await tester.tap(find.bySemanticsLabel('Reportar publicación'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar reporte'));
    await tester.pumpAndSettle();
    expect(find.text('El motivo del reporte es obligatorio.'), findsOneWidget);
  });

  testWidgets('compatibilidad 320 px', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail()},
    );
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;

    await openPostDetail(tester, gateway);
    await tester.tap(find.bySemanticsLabel('Reportar publicación'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('cancelación vuelve al detalle', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail()},
    );
    await openPostDetail(tester, gateway);
    await tester.tap(find.bySemanticsLabel('Reportar publicación'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(PostDetailScreen), findsOneWidget);
  });

  testWidgets('accesibilidad en acción del detalle', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail()},
    );
    await openPostDetail(tester, gateway);
    expect(find.bySemanticsLabel('Reportar publicación'), findsOneWidget);
  });

  testWidgets('sin sesión muestra aviso', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith(_GuestAuth.new)],
        child: const MaterialApp(home: PostReportScreen(postId: 1)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Inicia sesión para reportar contenido.'), findsOneWidget);
  });

  testWidgets('ausencia de POST desde UI', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail()},
    );
    await openPostDetail(tester, gateway);
    await tester.tap(find.bySemanticsLabel('Reportar publicación'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Spam o publicidad no deseada'));
    await tester.tap(find.text('Enviar reporte'));
    await tester.pumpAndSettle();
    expect(gateway.reportPostCallCount, 0);
  });

  testWidgets('enviar reporte habilitado sin POST hasta confirmar', (
    tester,
  ) async {
    final gateway = FakePostGateway(
      detailById: {1: sampleCommunityPostDetail()},
    );
    await openPostDetail(tester, gateway);
    await tester.tap(find.bySemanticsLabel('Reportar publicación'));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Enviar reporte'),
    );
    expect(button.onPressed, isNotNull);
    expect(gateway.reportPostCallCount, 0);
  });
}

class _GuestAuth extends AuthController {
  @override
  AuthState build() => const AuthUnauthenticated();
}
