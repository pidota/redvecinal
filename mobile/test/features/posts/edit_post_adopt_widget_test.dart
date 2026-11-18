import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/application/edit_post_controller.dart';
import 'package:red_vecinal/features/posts/application/edit_post_uncertain_patch_persistence.dart';
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
    c.read(editPostUncertainPatchPersistenceProvider);
    return c;
  }

  testWidgets('22 diálogo de confirmación para adopción', (tester) async {
    final gateway = FakePostGateway(
      detailById: {
        330: draftPostDetail(
          id: 330,
          groupId: 2,
          categoryId: 2,
          title: 'Old',
          body: 'Old',
        ),
      },
      postCategories: categories,
      updateFailureByPostId: {330: const ApiNetworkFailure()},
    );
    final c = container(gateway);
    addTearDown(c.dispose);
    await c.read(editPostControllerProvider(330).future);
    await c
        .read(editPostControllerProvider(330).notifier)
        .save(categoryId: 2, title: 'Match', body: 'Match');
    gateway.detailById![330] = draftPostDetail(
      id: 330,
      groupId: 2,
      categoryId: 2,
      title: 'Match',
      body: 'Match',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: EditPostScreen(postId: 330)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Verificar en servidor'));
    await tester.pumpAndSettle();

    expect(find.text('Usar estado del servidor'), findsOneWidget);
    expect(find.text('Conservar incertidumbre'), findsOneWidget);
    await tester.tap(find.text('Usar estado del servidor'));
    await tester.pumpAndSettle();

    expect(
      c.read(editPostControllerProvider(330)).requireValue.patchUncertain,
      isFalse,
    );
  });

  testWidgets('conflicto: diálogo y conservar incertidumbre', (tester) async {
    final gateway = FakePostGateway(
      detailById: {
        332: draftPostDetail(
          id: 332,
          groupId: 2,
          categoryId: 2,
          title: 'Old',
          body: 'Old',
        ),
      },
      postCategories: categories,
      updateFailureByPostId: {332: const ApiNetworkFailure()},
    );
    final c = container(gateway);
    addTearDown(c.dispose);
    await c.read(editPostControllerProvider(332).future);
    await c
        .read(editPostControllerProvider(332).notifier)
        .save(categoryId: 2, title: 'Local', body: 'Local');
    gateway.detailById![332] = draftPostDetail(
      id: 332,
      groupId: 2,
      categoryId: 2,
      title: 'Remote',
      body: 'Remote',
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: EditPostScreen(postId: 332)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verificar en servidor'));
    await tester.pumpAndSettle();

    expect(find.text('Versión distinta en el servidor'), findsOneWidget);
    await tester.tap(find.text('Conservar incertidumbre'));
    await tester.pumpAndSettle();
    expect(
      c.read(editPostControllerProvider(332)).requireValue.patchUncertain,
      isTrue,
    );
  });

  testWidgets('conflicto: truncamiento de texto largo', (tester) async {
    final longBody = 'L${'o' * 400}';
    final gateway = FakePostGateway(
      detailById: {
        333: draftPostDetail(
          id: 333,
          groupId: 2,
          categoryId: 2,
          title: 'Old',
          body: 'Short',
        ),
      },
      postCategories: categories,
      updateFailureByPostId: {333: const ApiNetworkFailure()},
    );
    final c = container(gateway);
    addTearDown(c.dispose);
    await c.read(editPostControllerProvider(333).future);
    await c
        .read(editPostControllerProvider(333).notifier)
        .save(categoryId: 2, title: 'Local', body: longBody);
    gateway.detailById![333] = draftPostDetail(
      id: 333,
      groupId: 2,
      categoryId: 2,
      title: 'Remote',
      body: longBody,
    );

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: EditPostScreen(postId: 333)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Verificar en servidor'));
    await tester.pumpAndSettle();

    expect(find.textContaining('caracteres en total'), findsWidgets);
  });

  testWidgets('viewport 320px: diálogo accesible', (tester) async {
    final gateway = FakePostGateway(
      detailById: {
        334: draftPostDetail(
          id: 334,
          groupId: 2,
          categoryId: 2,
          title: 'A',
          body: 'B',
        ),
      },
      postCategories: categories,
      updateFailureByPostId: {334: const ApiNetworkFailure()},
    );
    final c = container(gateway);
    addTearDown(c.dispose);
    await c.read(editPostControllerProvider(334).future);
    await c
        .read(editPostControllerProvider(334).notifier)
        .save(categoryId: 2, title: 'M', body: 'M');
    gateway.detailById![334] = draftPostDetail(
      id: 334,
      groupId: 2,
      categoryId: 2,
      title: 'M',
      body: 'M',
    );

    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: EditPostScreen(postId: 334)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Verificar en servidor'));
    await tester.tap(find.text('Verificar en servidor'));
    await tester.pumpAndSettle();

    expect(find.text('Usar estado del servidor'), findsOneWidget);
    await tester.ensureVisible(find.text('Usar estado del servidor'));
    await tester.tap(find.text('Usar estado del servidor'));
    await tester.pumpAndSettle();
    expect(
      c.read(editPostControllerProvider(334)).requireValue.patchUncertain,
      isFalse,
    );
  });

  testWidgets('23 banner restaurado tras reentrada', (tester) async {
    final gateway = FakePostGateway(
      detailById: {
        331: draftPostDetail(
          id: 331,
          groupId: 2,
          categoryId: 2,
          title: 'Inicio',
          body: 'Inicio',
        ),
      },
      postCategories: categories,
      updateFailureByPostId: {331: const ApiNetworkFailure()},
    );
    final c = container(gateway);
    addTearDown(c.dispose);
    await c.read(editPostControllerProvider(331).future);
    await c
        .read(editPostControllerProvider(331).notifier)
        .save(categoryId: 2, title: 'Inc', body: 'Inc');
    c.invalidate(editPostControllerProvider(331));

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: const MaterialApp(home: EditPostScreen(postId: 331)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('incierto'), findsWidgets);
    expect(find.text('Verificar en servidor'), findsOneWidget);
    expect(
      c.read(editPostControllerProvider(331)).requireValue.patchUncertain,
      isTrue,
    );
  });
}
