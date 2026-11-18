import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/application/edit_post_controller.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

void main() {
  ProviderContainer buildContainer(FakePostGateway gateway) {
    return ProviderContainer(
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
  }

  PostDetail detailFor(int id) =>
      draftPostDetail(id: id, groupId: 2, categoryId: 2, title: 'T', body: 'B');

  ProviderSubscription<AsyncValue<EditPostSession>> keepEditPostAlive(
    ProviderContainer c,
    int postId,
  ) {
    return c.listen(editPostControllerProvider(postId), (_, __) {});
  }

  group('4C.2B.1 hardening PATCH', () {
    test('1 ApiNetworkFailure activa incertidumbre', () async {
      final gateway = FakePostGateway(
        detailById: {201: detailFor(201)},
        updateFailureByPostId: {201: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(201).future);
      final result = await c
          .read(editPostControllerProvider(201).notifier)
          .save(categoryId: 2, title: 'N', body: 'N');
      expect(result, isA<EditPostSaveUncertain>());
      expect(
        c.read(editPostControllerProvider(201)).requireValue.patchUncertain,
        isTrue,
      );
    });

    test('2 ApiTimeoutFailure activa incertidumbre', () async {
      final gateway = FakePostGateway(
        detailById: {202: detailFor(202)},
        updateFailureByPostId: {202: const ApiTimeoutFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(202).future);
      final result = await c
          .read(editPostControllerProvider(202).notifier)
          .save(categoryId: 2, title: 'N', body: 'N');
      expect(result, isA<EditPostSaveUncertain>());
      expect(
        c.read(editPostControllerProvider(202)).requireValue.patchUncertain,
        isTrue,
      );
    });

    test('3 ApiServerFailure activa incertidumbre', () async {
      final gateway = FakePostGateway(
        detailById: {203: detailFor(203)},
        updateFailureByPostId: {203: const ApiServerFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(203).future);
      final result = await c
          .read(editPostControllerProvider(203).notifier)
          .save(categoryId: 2, title: 'N', body: 'N');
      expect(result, isA<EditPostSaveUncertain>());
      expect(
        c.read(editPostControllerProvider(203)).requireValue.patchUncertain,
        isTrue,
      );
    });

    test('4 HTTP 422 es error confirmado', () async {
      final gateway = FakePostGateway(
        detailById: {204: detailFor(204)},
        updateFailureByPostId: {
          204: const ApiValidationFailure({
            'title': ['inválido'],
          }),
        },
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(204).future);
      final result = await c
          .read(editPostControllerProvider(204).notifier)
          .save(categoryId: 2, title: 'T', body: 'B');
      expect(result, isA<EditPostSaveFailure>());
      expect(
        c.read(editPostControllerProvider(204)).requireValue.patchUncertain,
        isFalse,
      );
    });

    test('5 HTTP 403 es error confirmado', () async {
      final gateway = FakePostGateway(
        detailById: {205: detailFor(205)},
        updateFailureByPostId: {205: const ApiForbiddenFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(205).future);
      final result = await c
          .read(editPostControllerProvider(205).notifier)
          .save(categoryId: 2, title: 'T', body: 'B');
      expect(result, isA<EditPostSaveFailure>());
      expect(
        c.read(editPostControllerProvider(205)).requireValue.patchUncertain,
        isFalse,
      );
    });

    test('6 HTTP 401 es error confirmado', () async {
      final gateway = FakePostGateway(
        detailById: {206: detailFor(206)},
        updateFailureByPostId: {206: const ApiSessionExpiredFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(206).future);
      final result = await c
          .read(editPostControllerProvider(206).notifier)
          .save(categoryId: 2, title: 'T', body: 'B');
      expect(result, isA<EditPostSaveFailure>());
      expect(
        (result as EditPostSaveFailure).failure,
        isA<ApiSessionExpiredFailure>(),
      );
    });

    test('7 reload durante PATCH no habilita segundo save', () async {
      final gateway = FakePostGateway(
        detailById: {207: detailFor(207)},
        updateDelayMs: 120,
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      final alive = keepEditPostAlive(c, 207);
      addTearDown(alive.close);
      await c.read(editPostControllerProvider(207).future);
      final notifier = c.read(editPostControllerProvider(207).notifier);
      final first = notifier.save(categoryId: 2, title: 'A', body: 'A');
      await notifier.reload();
      final second = await notifier.save(categoryId: 2, title: 'C', body: 'D');
      expect(second, isA<EditPostSaveInFlight>());
      expect(gateway.updatePostCallCount, 1);
      await first;
      expect(
        c.read(editPostControllerProvider(207)).requireValue.saveInFlight,
        isFalse,
      );
    });

    test('8 reload durante PATCH exitoso mantiene coherencia', () async {
      final gateway = FakePostGateway(
        detailById: {208: detailFor(208)},
        updateDelayMs: 80,
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      final alive = keepEditPostAlive(c, 208);
      addTearDown(alive.close);
      await c.read(editPostControllerProvider(208).future);
      final notifier = c.read(editPostControllerProvider(208).notifier);
      final op = notifier.save(categoryId: 2, title: 'OK', body: 'OK');
      await notifier.reload();
      expect(notifier.isPatchInFlight, isTrue);
      final result = await op;
      expect(result, isA<EditPostSaveSuccess>());
      expect(gateway.updatePostCallCount, 1);
      expect(
        c
            .read(editPostControllerProvider(208))
            .requireValue
            .snapshot
            .detail
            .workingContent!
            .title,
        'OK',
      );
    });

    test('9 reload durante PATCH incierto conserva incertidumbre', () async {
      final gateway = FakePostGateway(
        detailById: {209: detailFor(209)},
        updateDelayMs: 80,
        updateFailureByPostId: {209: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      final alive = keepEditPostAlive(c, 209);
      addTearDown(alive.close);
      await c.read(editPostControllerProvider(209).future);
      final notifier = c.read(editPostControllerProvider(209).notifier);
      final op = notifier.save(categoryId: 2, title: 'U', body: 'U');
      await notifier.reload();
      await op;
      expect(
        c.read(editPostControllerProvider(209)).requireValue.patchUncertain,
        isTrue,
      );
      final blocked = await notifier.save(
        categoryId: 2,
        title: 'U2',
        body: 'U2',
      );
      expect(blocked, isA<EditPostSaveBlocked>());
      expect(gateway.updatePostCallCount, 1);
    });

    test('10 logout durante PATCH y luego reload', () async {
      final gateway = FakePostGateway(
        detailById: {210: detailFor(210)},
        updateDelayMs: 100,
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      final alive = keepEditPostAlive(c, 210);
      addTearDown(alive.close);
      await c.read(editPostControllerProvider(210).future);
      final notifier = c.read(editPostControllerProvider(210).notifier);
      final op = notifier.save(categoryId: 2, title: 'L', body: 'L');
      await c.read(authControllerProvider.notifier).logout(localOnly: true);
      final result = await op;
      expect(result, isA<EditPostSaveDiscarded>());
      await notifier.reload();
      final after = c.read(editPostControllerProvider(210));
      expect(after.hasError || after.valueOrNull == null, isTrue);
    });

    test('11 GET coincidente no afirma éxito PATCH', () async {
      final gateway = FakePostGateway(
        detailById: {
          211: draftPostDetail(
            id: 211,
            groupId: 2,
            categoryId: 2,
            title: 'Old',
            body: 'Old',
          ),
        },
        updateFailureByPostId: {211: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(211).future);
      final notifier = c.read(editPostControllerProvider(211).notifier);
      await notifier.save(categoryId: 2, title: 'Match', body: 'Body');
      gateway.updateFailureByPostId!.remove(211);
      gateway.detailById![211] = draftPostDetail(
        id: 211,
        groupId: 2,
        categoryId: 2,
        title: 'Match',
        body: 'Body',
      );
      final reconcile = await notifier.reconcileUncertainPatch();
      expect(reconcile, isA<EditPostReconcileObservableMatch>());
      expect(reconcile, isNot(isA<EditPostSaveSuccess>()));
    });

    test(
      '12 GET coincidente no limpia incertidumbre automáticamente',
      () async {
        final gateway = FakePostGateway(
          detailById: {212: detailFor(212)},
          updateFailureByPostId: {212: const ApiNetworkFailure()},
        );
        final c = buildContainer(gateway);
        addTearDown(c.dispose);
        await c.read(editPostControllerProvider(212).future);
        final notifier = c.read(editPostControllerProvider(212).notifier);
        await notifier.save(categoryId: 2, title: 'Same', body: 'Same');
        gateway.detailById![212] = draftPostDetail(
          id: 212,
          groupId: 2,
          categoryId: 2,
          title: 'Same',
          body: 'Same',
        );
        await notifier.reconcileUncertainPatch();
        expect(
          c.read(editPostControllerProvider(212)).requireValue.patchUncertain,
          isTrue,
        );
      },
    );

    test('13 GET divergente conserva texto local en snapshot', () async {
      final gateway = FakePostGateway(
        detailById: {213: detailFor(213)},
        updateFailureByPostId: {213: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(213).future);
      final notifier = c.read(editPostControllerProvider(213).notifier);
      await notifier.save(categoryId: 2, title: 'Local', body: 'Local');
      gateway.detailById![213] = draftPostDetail(
        id: 213,
        groupId: 2,
        categoryId: 2,
        title: 'Remote',
        body: 'Remote',
      );
      final reconcile = await notifier.reconcileUncertainPatch();
      expect(reconcile, isA<EditPostReconcileRemoteConflict>());
      expect(
        c
            .read(editPostControllerProvider(213))
            .requireValue
            .snapshot
            .detail
            .workingContent!
            .title,
        'T',
      );
    });

    test('14 GET fallido conserva incertidumbre', () async {
      final gateway = FakePostGateway(
        detailById: {214: detailFor(214)},
        updateFailureByPostId: {214: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(214).future);
      final notifier = c.read(editPostControllerProvider(214).notifier);
      await notifier.save(categoryId: 2, title: 'X', body: 'X');
      gateway.detailFailureById = {214: const ApiNetworkFailure()};
      final reconcile = await notifier.reconcileUncertainPatch();
      expect(reconcile, isA<EditPostReconcileStillUncertain>());
      expect(
        c.read(editPostControllerProvider(214)).requireValue.patchUncertain,
        isTrue,
      );
    });

    test(
      '15 snapshot enviado permanece inmutable con segundo save bloqueado',
      () async {
        String? patchedTitle;
        final gateway = FakePostGateway(
          detailById: {215: detailFor(215)},
          updateDelayMs: 100,
          onUpdatePost: (_, __, title, ___) => patchedTitle = title,
        );
        final c = buildContainer(gateway);
        addTearDown(c.dispose);
        await c.read(editPostControllerProvider(215).future);
        final notifier = c.read(editPostControllerProvider(215).notifier);
        final first = notifier.save(
          categoryId: 2,
          title: 'Immutable',
          body: 'Body',
        );
        await notifier.save(categoryId: 2, title: 'Changed', body: 'Changed');
        await first;
        expect(patchedTitle, 'Immutable');
        expect(gateway.updatePostCallCount, 1);
      },
    );

    test('16 respuesta tardía no altera otra sesión', () async {
      final gateway = FakePostGateway(
        detailById: {216: detailFor(216)},
        updateDelayMs: 120,
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      final alive = keepEditPostAlive(c, 216);
      addTearDown(alive.close);
      await c.read(editPostControllerProvider(216).future);
      final op = c
          .read(editPostControllerProvider(216).notifier)
          .save(categoryId: 2, title: 'Late', body: 'Late');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await c.read(authControllerProvider.notifier).logout(localOnly: true);
      final result = await op;
      expect(result, isA<EditPostSaveDiscarded>());
      final session = c.read(editPostControllerProvider(216));
      expect(session.hasError, isTrue);
      expect(session.valueOrNull?.snapshot.detail.workingContent?.title, 'T');
    });

    test('17 sin PATCH automático tras reconciliación', () async {
      final gateway = FakePostGateway(
        detailById: {217: detailFor(217)},
        updateFailureByPostId: {217: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(217).future);
      final notifier = c.read(editPostControllerProvider(217).notifier);
      await notifier.save(categoryId: 2, title: 'R', body: 'R');
      gateway.detailById![217] = draftPostDetail(
        id: 217,
        groupId: 2,
        categoryId: 2,
        title: 'R',
        body: 'R',
      );
      await notifier.reconcileUncertainPatch();
      final retry = await notifier.save(categoryId: 2, title: 'R', body: 'R');
      expect(retry, isA<EditPostSaveBlocked>());
      expect(gateway.updatePostCallCount, 1);
    });

    test('18 sin regresión de creación de publicaciones', () async {
      final gateway = FakePostGateway(detailById: {218: detailFor(218)});
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(218).future);
      await c
          .read(editPostControllerProvider(218).notifier)
          .save(categoryId: 2, title: 'N', body: 'N');
      expect(gateway.createPostCallCount, 0);
      expect(gateway.updatePostCallCount, 1);
    });
  });
}
