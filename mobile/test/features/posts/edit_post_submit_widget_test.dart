import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/application/edit_post_attachments_persistence.dart';
import 'package:red_vecinal/features/posts/application/edit_post_controller.dart';
import 'package:red_vecinal/features/posts/application/edit_post_uncertain_submit_persistence.dart';
import 'package:red_vecinal/features/posts/data/models/post_category.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';
import 'package:red_vecinal/features/posts/presentation/edit_post_screen.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

void main() {
  const categories = [
    PostCategory(
      id: 2,
      slug: 'aviso-comunitario',
      name: 'Aviso comunitario',
      defaultAudience: 'group',
      sortOrder: 1,
      isSystem: true,
    ),
  ];

  ProviderContainer container(FakePostGateway gateway) {
    final c = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        postRepositoryProvider.overrideWithValue(gateway),
        authControllerProvider.overrideWith(
          AuthenticatedBootAuthController.new,
        ),
      ],
    );
    c.read(editPostAttachmentsPersistenceProvider);
    c.read(editPostUncertainSubmitPersistenceProvider);
    return c;
  }

  Future<void> setViewport320(WidgetTester tester) {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    return Future<void>.value();
  }

  Future<void> confirmAndSend(WidgetTester tester) async {
    if (find.text('Enviar a revisión').evaluate().isNotEmpty) {
      await tester.tap(find.text('Enviar a revisión'));
    } else {
      await tester.tap(find.text('Reenviar a revisión'));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('Enviar'));
    await tester.pumpAndSettle();
  }

  testWidgets('confirmación y botón enviar 320px', (tester) async {
    final gateway = FakePostGateway(
      detailById: {
        1201: draftPostDetail(
          id: 1201,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
      postCategories: categories,
    );
    final c = container(gateway);
    addTearDown(c.dispose);
    await setViewport320(tester);
    addTearDown(tester.view.resetPhysicalSize);
    await c.read(editPostControllerProvider(1201).future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: EditPostScreen(postId: 1201)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enviar a revisión'), findsOneWidget);
    await tester.tap(find.text('Enviar a revisión'));
    await tester.pumpAndSettle();
    expect(find.text('Enviar a moderación'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('error definitivo submit muestra snackbar', (tester) async {
    final gateway = FakePostGateway(
      detailById: {
        1202: draftPostDetail(
          id: 1202,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
      postCategories: categories,
      submitFailureByPostId: {1202: const ApiForbiddenFailure()},
    );
    final c = container(gateway);
    addTearDown(c.dispose);
    await setViewport320(tester);
    addTearDown(tester.view.resetPhysicalSize);
    await c.read(editPostControllerProvider(1202).future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: EditPostScreen(postId: 1202)),
      ),
    );
    await tester.pumpAndSettle();
    await confirmAndSend(tester);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(
      find.text('No tienes permiso para realizar esta acción.'),
      findsOneWidget,
    );
    expect(gateway.submitPostCallCount, 1);
  });

  testWidgets('submit incierto por red muestra banner y snackbar', (
    tester,
  ) async {
    final gateway = FakePostGateway(
      detailById: {
        1203: draftPostDetail(
          id: 1203,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
      postCategories: categories,
      submitFailureByPostId: {1203: const ApiNetworkFailure()},
    );
    final c = container(gateway);
    addTearDown(c.dispose);
    await setViewport320(tester);
    addTearDown(tester.view.resetPhysicalSize);
    await c.read(editPostControllerProvider(1203).future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: EditPostScreen(postId: 1203)),
      ),
    );
    await tester.pumpAndSettle();
    await confirmAndSend(tester);
    expect(find.textContaining('incierto', findRichText: true), findsWidgets);
    expect(find.text('Verificar estado del envío'), findsOneWidget);
    expect(
      find.textContaining('No confirmamos', findRichText: true),
      findsOneWidget,
    );
    expect(
      c.read(editPostControllerProvider(1203)).requireValue.submitUncertain,
      isTrue,
    );
  });

  testWidgets('reconcile pending observado sin afirmar envío HTTP', (
    tester,
  ) async {
    final gateway = FakePostGateway(
      detailById: {
        1204: draftPostDetail(
          id: 1204,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
      postCategories: categories,
      submitThrowsUncertain: true,
    );
    final c = container(gateway);
    addTearDown(c.dispose);
    await setViewport320(tester);
    addTearDown(tester.view.resetPhysicalSize);
    await c.read(editPostControllerProvider(1204).future);
    await c
        .read(editPostControllerProvider(1204).notifier)
        .submitToModeration(categoryId: 2, title: 'T', body: 'B');
    gateway.detailById![1204] = pendingPostDetail(id: 1204);
    final result =
        await c
            .read(editPostControllerProvider(1204).notifier)
            .reconcileUncertainSubmit();
    expect(result, isA<EditPostSubmitReconcileObservedPending>());
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) {
                return TextButton(
                  onPressed: () {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      SnackBar(
                        content: Text(
                          (result as EditPostSubmitReconcileObservedPending)
                              .message,
                        ),
                      ),
                    );
                  },
                  child: const Text('mostrar'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('mostrar'));
    await tester.pump();
    expect(
      find.textContaining('no confirma', findRichText: true),
      findsWidgets,
    );
    c.listen(editPostControllerProvider(1204), (_, __) {});
    final session = await c.read(editPostControllerProvider(1204).future);
    expect(session.submitUncertain, isTrue);
  });

  testWidgets('reconcile draft inconcluso conserva incertidumbre', (
    tester,
  ) async {
    final gateway = FakePostGateway(
      detailById: {
        1205: draftPostDetail(
          id: 1205,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
      postCategories: categories,
      submitThrowsUncertain: true,
    );
    final c = container(gateway);
    addTearDown(c.dispose);
    await c.read(editPostControllerProvider(1205).future);
    await c
        .read(editPostControllerProvider(1205).notifier)
        .submitToModeration(categoryId: 2, title: 'T', body: 'B');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: EditPostScreen(postId: 1205)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verificar estado del envío'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('no confirmamos', findRichText: true),
      findsWidgets,
    );
    expect(find.text('Verificar estado del envío'), findsOneWidget);
  });

  testWidgets('pending deshabilita edición y enviar', (tester) async {
    final gateway = FakePostGateway(
      detailById: {
        1206: draftPostDetail(
          id: 1206,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
      postCategories: categories,
    );
    final c = container(gateway);
    addTearDown(c.dispose);
    await setViewport320(tester);
    addTearDown(tester.view.resetPhysicalSize);
    await c.read(editPostControllerProvider(1206).future);
    await c
        .read(editPostControllerProvider(1206).notifier)
        .submitToModeration(categoryId: 2, title: 'T', body: 'B');
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: EditPostScreen(postId: 1206)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Enviar a revisión'), findsNothing);
    expect(find.text('No editable'), findsOneWidget);
    expect(find.textContaining('moderación', findRichText: true), findsWidgets);
    expect(find.text('Volver'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px sin overflow tras error de red en submit', (tester) async {
    final gateway = FakePostGateway(
      detailById: {
        1207: draftPostDetail(
          id: 1207,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
      postCategories: categories,
      submitFailureByPostId: {1207: const ApiNetworkFailure()},
    );
    final c = container(gateway);
    addTearDown(c.dispose);
    await setViewport320(tester);
    addTearDown(tester.view.resetPhysicalSize);
    await c.read(editPostControllerProvider(1207).future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: EditPostScreen(postId: 1207)),
      ),
    );
    await tester.pumpAndSettle();
    await confirmAndSend(tester);
    expect(tester.takeException(), isNull);
  });
}
