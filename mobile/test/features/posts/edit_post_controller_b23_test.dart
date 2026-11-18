import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/application/edit_post_controller.dart';
import 'package:red_vecinal/features/posts/application/edit_post_uncertain_patch_persistence.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

void main() {
  ProviderContainer buildContainer(
    FakePostGateway gateway, {
    bool persistenceEnabled = true,
  }) {
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
    c
        .read(editPostUncertainPatchPersistenceProvider.notifier)
        .persistenceCommitEnabled = persistenceEnabled;
    return c;
  }

  PostDetail detailFor(int id, {String title = 'T', String body = 'B'}) =>
      draftPostDetail(
        id: id,
        groupId: 2,
        categoryId: 2,
        title: title,
        body: body,
      );

  ProviderSubscription<AsyncValue<EditPostSession>> keepAlive(
    ProviderContainer c,
    int postId,
  ) {
    return c.listen(editPostControllerProvider(postId), (_, __) {});
  }

  group('4C.2B.3 persistencia y adopción', () {
    test('1 registro previo al PATCH', () async {
      final gateway = FakePostGateway(
        detailById: {301: detailFor(301)},
        updateDelayMs: 80,
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      final sub = keepAlive(c, 301);
      addTearDown(sub.close);
      await c.read(editPostControllerProvider(301).future);
      final op = c
          .read(editPostControllerProvider(301).notifier)
          .save(categoryId: 2, title: 'A', body: 'A');
      expect(
        c.read(editPostUncertainPatchPersistenceProvider).recordForPost(301),
        isNotNull,
      );
      await op;
    });

    test('2 fallo de persistencia bloquea PATCH', () async {
      final gateway = FakePostGateway(detailById: {302: detailFor(302)});
      final c = buildContainer(gateway, persistenceEnabled: false);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(302).future);
      final result = await c
          .read(editPostControllerProvider(302).notifier)
          .save(categoryId: 2, title: 'X', body: 'X');
      expect(result, isA<EditPostSaveBlocked>());
      expect(gateway.updatePostCallCount, 0);
    });

    test('3 HTTP 200 limpia registro', () async {
      final gateway = FakePostGateway(detailById: {303: detailFor(303)});
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(303).future);
      await c
          .read(editPostControllerProvider(303).notifier)
          .save(categoryId: 2, title: 'OK', body: 'OK');
      expect(
        c.read(editPostUncertainPatchPersistenceProvider).recordForPost(303),
        isNull,
      );
    });

    test('4 timeout conserva registro', () async {
      final gateway = FakePostGateway(
        detailById: {304: detailFor(304)},
        updateFailureByPostId: {304: const ApiTimeoutFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(304).future);
      await c
          .read(editPostControllerProvider(304).notifier)
          .save(categoryId: 2, title: 'T', body: 'T');
      final record = c
          .read(editPostUncertainPatchPersistenceProvider)
          .recordForPost(304);
      expect(record, isNotNull);
      expect(record!.title, 'T');
    });

    test('5 network failure conserva registro', () async {
      final gateway = FakePostGateway(
        detailById: {305: detailFor(305)},
        updateFailureByPostId: {305: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(305).future);
      await c
          .read(editPostControllerProvider(305).notifier)
          .save(categoryId: 2, title: 'N', body: 'N');
      expect(
        c.read(editPostUncertainPatchPersistenceProvider).recordForPost(305),
        isNotNull,
      );
    });

    test('6 HTTP 500 conserva registro', () async {
      final gateway = FakePostGateway(
        detailById: {306: detailFor(306)},
        updateFailureByPostId: {306: const ApiServerFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(306).future);
      await c
          .read(editPostControllerProvider(306).notifier)
          .save(categoryId: 2, title: 'S', body: 'S');
      expect(
        c.read(editPostUncertainPatchPersistenceProvider).recordForPost(306),
        isNotNull,
      );
    });

    test('7 GET coincidente conserva registro', () async {
      final gateway = FakePostGateway(
        detailById: {307: detailFor(307)},
        updateFailureByPostId: {307: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(307).future);
      final notifier = c.read(editPostControllerProvider(307).notifier);
      await notifier.save(categoryId: 2, title: 'M', body: 'M');
      gateway.detailById![307] = detailFor(307, title: 'M', body: 'M');
      await notifier.reconcileUncertainPatch();
      expect(
        c.read(editPostUncertainPatchPersistenceProvider).recordForPost(307),
        isNotNull,
      );
    });

    test('8 GET divergente conserva registro', () async {
      final gateway = FakePostGateway(
        detailById: {308: detailFor(308)},
        updateFailureByPostId: {308: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(308).future);
      final notifier = c.read(editPostControllerProvider(308).notifier);
      await notifier.save(categoryId: 2, title: 'L', body: 'L');
      gateway.detailById![308] = detailFor(308, title: 'R', body: 'R');
      await notifier.reconcileUncertainPatch();
      expect(
        c.read(editPostUncertainPatchPersistenceProvider).recordForPost(308),
        isNotNull,
      );
    });

    test('9 GET fallido conserva registro', () async {
      final gateway = FakePostGateway(
        detailById: {309: detailFor(309)},
        updateFailureByPostId: {309: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(309).future);
      final notifier = c.read(editPostControllerProvider(309).notifier);
      await notifier.save(categoryId: 2, title: 'X', body: 'X');
      gateway.detailFailureById = {309: const ApiNetworkFailure()};
      await notifier.reconcileUncertainPatch();
      expect(
        c.read(editPostUncertainPatchPersistenceProvider).recordForPost(309),
        isNotNull,
      );
    });

    test('10 reentrada tras AutoDispose', () async {
      final gateway = FakePostGateway(
        detailById: {310: detailFor(310)},
        updateFailureByPostId: {310: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(310).future);
      await c
          .read(editPostControllerProvider(310).notifier)
          .save(categoryId: 2, title: 'P', body: 'P');
      c.invalidate(editPostControllerProvider(310));
      await c.read(editPostControllerProvider(310).future);
      final session = c.read(editPostControllerProvider(310)).requireValue;
      expect(session.patchUncertain, isTrue);
      final blocked = await c
          .read(editPostControllerProvider(310).notifier)
          .save(categoryId: 2, title: 'P2', body: 'P2');
      expect(blocked, isA<EditPostSaveBlocked>());
    });

    test('11 reinicio de provider mantiene registro', () async {
      final gateway = FakePostGateway(
        detailById: {311: detailFor(311)},
        updateFailureByPostId: {311: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      final sub = keepAlive(c, 311);
      addTearDown(sub.close);
      await c.read(editPostControllerProvider(311).future);
      await c
          .read(editPostControllerProvider(311).notifier)
          .save(categoryId: 2, title: 'K', body: 'K');
      c.invalidate(editPostUncertainPatchPersistenceProvider);
      expect(
        c.read(editPostUncertainPatchPersistenceProvider).recordForPost(311),
        isNotNull,
      );
    });

    test('12 aislamiento por postId', () async {
      final gateway = FakePostGateway(
        detailById: {312: detailFor(312), 313: detailFor(313)},
        updateFailureByPostId: {312: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(312).future);
      await c.read(editPostControllerProvider(313).future);
      await c
          .read(editPostControllerProvider(312).notifier)
          .save(categoryId: 2, title: 'A', body: 'A');
      expect(
        c.read(editPostControllerProvider(313)).requireValue.patchUncertain,
        isFalse,
      );
    });

    test('13 aislamiento por sesión tras logout', () async {
      final gateway = FakePostGateway(
        detailById: {314: detailFor(314)},
        updateFailureByPostId: {314: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(314).future);
      await c
          .read(editPostControllerProvider(314).notifier)
          .save(categoryId: 2, title: 'U', body: 'U');
      await c.read(authControllerProvider.notifier).logout(localOnly: true);
      expect(
        c.read(editPostUncertainPatchPersistenceProvider).recordForPost(314),
        isNull,
      );
    });

    test('14 logout durante PATCH descarta sin contaminar', () async {
      final gateway = FakePostGateway(
        detailById: {315: detailFor(315)},
        updateDelayMs: 100,
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      final sub = keepAlive(c, 315);
      addTearDown(sub.close);
      await c.read(editPostControllerProvider(315).future);
      final op = c
          .read(editPostControllerProvider(315).notifier)
          .save(categoryId: 2, title: 'L', body: 'L');
      await c.read(authControllerProvider.notifier).logout(localOnly: true);
      expect(await op, isA<EditPostSaveDiscarded>());
    });

    test('15 limpieza tardía no borra intento nuevo', () async {
      final gateway = FakePostGateway(
        detailById: {316: detailFor(316)},
        updateFailureByPostId: {316: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      final persistence = c.read(
        editPostUncertainPatchPersistenceProvider.notifier,
      );
      await c.read(editPostControllerProvider(316).future);
      await c
          .read(editPostControllerProvider(316).notifier)
          .save(categoryId: 2, title: 'Old', body: 'Old');
      final firstGen =
          c
              .read(editPostUncertainPatchPersistenceProvider)
              .recordForPost(316)!
              .operationGeneration;
      persistence.beginPatchAttempt(
        userId: 1,
        sessionEpoch: c.read(authControllerProvider.notifier).sessionEpoch,
        postId: 316,
        revisionId: 3160,
        categoryId: 2,
        title: 'New',
        body: 'New',
      );
      final secondGen =
          c
              .read(editPostUncertainPatchPersistenceProvider)
              .recordForPost(316)!
              .operationGeneration;
      expect(secondGen, greaterThan(firstGen));
      persistence.confirmPatchSuccess(316, firstGen);
      expect(
        c
            .read(editPostUncertainPatchPersistenceProvider)
            .recordForPost(316)!
            .operationGeneration,
        secondGen,
      );
    });

    test('16 adopción sin GET previo bloqueada', () async {
      final gateway = FakePostGateway(
        detailById: {317: detailFor(317)},
        updateFailureByPostId: {317: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(317).future);
      await c
          .read(editPostControllerProvider(317).notifier)
          .save(categoryId: 2, title: 'A', body: 'A');
      final adopt =
          c
              .read(editPostControllerProvider(317).notifier)
              .adoptObservedServerState();
      expect(adopt, isA<EditPostAdoptBlocked>());
    });

    test('17 adopción con postId distinto bloqueada', () async {
      final gateway = FakePostGateway(
        detailById: {318: detailFor(318)},
        updateFailureByPostId: {318: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(318).future);
      final notifier = c.read(editPostControllerProvider(318).notifier);
      await notifier.save(categoryId: 2, title: 'A', body: 'A');
      gateway.detailById![318] = detailFor(318, title: 'A', body: 'A');
      await notifier.reconcileUncertainPatch();
      notifier.debugReplaceObservationRemote(detailFor(999));
      final adopt = notifier.adoptObservedServerState();
      expect(adopt, isA<EditPostAdoptBlocked>());
    });

    test('18 adopción con revisión distinta bloqueada', () async {
      final gateway = FakePostGateway(
        detailById: {
          319: draftPostDetail(
            id: 319,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
            revisionId: 100,
          ),
        },
        updateFailureByPostId: {319: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(319).future);
      final notifier = c.read(editPostControllerProvider(319).notifier);
      await notifier.save(categoryId: 2, title: 'A', body: 'A');
      gateway.detailById![319] = draftPostDetail(
        id: 319,
        groupId: 2,
        categoryId: 2,
        title: 'A',
        body: 'A',
        revisionId: 200,
      );
      await notifier.reconcileUncertainPatch();
      final adopt = notifier.adoptObservedServerState();
      expect(adopt, isA<EditPostAdoptBlocked>());
    });

    test('19 adopción con observación antigua bloqueada', () async {
      final gateway = FakePostGateway(
        detailById: {320: detailFor(320)},
        updateFailureByPostId: {320: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(320).future);
      final notifier = c.read(editPostControllerProvider(320).notifier);
      await notifier.save(categoryId: 2, title: 'A', body: 'A');
      gateway.detailById![320] = detailFor(320, title: 'A', body: 'A');
      await notifier.reconcileUncertainPatch();
      notifier.debugInvalidateReconcileObservation();
      final adopt = notifier.adoptObservedServerState();
      expect(adopt, isA<EditPostAdoptBlocked>());
    });

    test('20 adopción explícita exitosa', () async {
      final gateway = FakePostGateway(
        detailById: {321: detailFor(321)},
        updateFailureByPostId: {321: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(321).future);
      final notifier = c.read(editPostControllerProvider(321).notifier);
      await notifier.save(categoryId: 2, title: 'Adopt', body: 'Adopt');
      gateway.detailById![321] = detailFor(321, title: 'Adopt', body: 'Adopt');
      await notifier.reconcileUncertainPatch();
      final adopt = notifier.adoptObservedServerState();
      expect(adopt, isA<EditPostAdoptSuccess>());
      expect(
        c.read(editPostControllerProvider(321)).requireValue.patchUncertain,
        isFalse,
      );
      expect(
        c.read(editPostUncertainPatchPersistenceProvider).recordForPost(321),
        isNull,
      );
    });

    test('21 conflicto conserva texto local hasta confirmar', () async {
      final gateway = FakePostGateway(
        detailById: {322: detailFor(322)},
        updateFailureByPostId: {322: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(322).future);
      final notifier = c.read(editPostControllerProvider(322).notifier);
      await notifier.save(categoryId: 2, title: 'Local', body: 'Local');
      gateway.detailById![322] = detailFor(
        322,
        title: 'Remote',
        body: 'Remote',
      );
      final reconcile = await notifier.reconcileUncertainPatch();
      expect(reconcile, isA<EditPostReconcileRemoteConflict>());
      expect(
        c.read(editPostControllerProvider(322)).requireValue.patchUncertain,
        isTrue,
      );
      expect(notifier.pendingUncertainPayload!.title, 'Local');
    });

    test('24 sin PATCH automático al restaurar', () async {
      final gateway = FakePostGateway(
        detailById: {324: detailFor(324)},
        updateFailureByPostId: {324: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(324).future);
      await c
          .read(editPostControllerProvider(324).notifier)
          .save(categoryId: 2, title: 'R', body: 'R');
      c.invalidate(editPostControllerProvider(324));
      await c.read(editPostControllerProvider(324).future);
      expect(gateway.updatePostCallCount, 1);
    });

    test('25 sin regresión de creación de publicaciones', () async {
      final gateway = FakePostGateway(detailById: {325: detailFor(325)});
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(325).future);
      await c
          .read(editPostControllerProvider(325).notifier)
          .save(categoryId: 2, title: 'N', body: 'N');
      expect(gateway.createPostCallCount, 0);
    });
  });
}
