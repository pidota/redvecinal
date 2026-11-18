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

  group('hidratación GET', () {
    test('1 draft editable con working_content', () async {
      final detail = draftPostDetail(
        id: 50,
        groupId: 2,
        categoryId: 2,
        title: 'B',
        body: 'Cuerpo',
      );
      final snap = EditPostSnapshot.fromDetail(detail);
      expect(snap.editable, isTrue);
      expect(snap.editableRevisionId, 500);
    });

    test('2 rejected editable', () async {
      final detail = rejectedPostDetail(
        id: 51,
        groupId: 2,
        categoryId: 2,
        title: 'R',
        body: 'Rechazado',
      );
      final snap = EditPostSnapshot.fromDetail(detail);
      expect(snap.editable, isTrue);
    });

    test('3 pending bloqueado', () {
      final snap = EditPostSnapshot.fromDetail(pendingPostDetail(id: 52));
      expect(snap.editable, isFalse);
    });

    test('4 published bloqueado', () {
      final snap = EditPostSnapshot.fromDetail(
        sampleCommunityPostDetail(id: 53),
      );
      expect(snap.editable, isFalse);
    });

    test('5 sin working_content bloqueado', () {
      final json = Map<String, dynamic>.from(mineDraftPostJson(id: 54));
      json['working_content'] = null;
      final detail = PostDetail.fromJson(json);
      final snap = EditPostSnapshot.fromDetail(detail);
      expect(snap.editable, isFalse);
    });
  });

  test('6 PATCH draft exitoso', () async {
    final gateway = FakePostGateway(
      detailById: {
        60: draftPostDetail(
          id: 60,
          groupId: 2,
          categoryId: 2,
          title: 'A',
          body: 'Uno',
        ),
      },
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);
    final keep = c.listen(editPostControllerProvider(60), (_, __) {});

    await c.read(editPostControllerProvider(60).future);
    final result = await c
        .read(editPostControllerProvider(60).notifier)
        .save(categoryId: 2, title: 'Nuevo', body: 'Dos');
    expect(result, isA<EditPostSaveSuccess>());
    expect(gateway.updatePostCallCount, 1);
    expect(gateway.createPostCallCount, 0);
    keep.close();
  });

  test('7 PATCH rejected exitoso', () async {
    final gateway = FakePostGateway(
      detailById: {
        61: rejectedPostDetail(
          id: 61,
          groupId: 2,
          categoryId: 2,
          title: 'R',
          body: 'Txt',
        ),
      },
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);
    await c.read(editPostControllerProvider(61).future);
    final result = await c
        .read(editPostControllerProvider(61).notifier)
        .save(categoryId: 2, title: 'Fix', body: 'Corregido');
    expect(result, isA<EditPostSaveSuccess>());
    final success = result as EditPostSaveSuccess;
    expect(success.detail.status, 'rejected');
    expect(gateway.updatePostCallCount, 1);
  });

  test('8 PATCH conserva revision_id', () async {
    const revision = 888;
    final gateway = FakePostGateway(
      detailById: {
        62: draftPostDetail(
          id: 62,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
          revisionId: revision,
        ),
      },
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);
    await c.read(editPostControllerProvider(62).future);
    await c
        .read(editPostControllerProvider(62).notifier)
        .save(categoryId: 2, title: 'T2', body: 'B2');
    final session = c.read(editPostControllerProvider(62)).requireValue;
    expect(session.snapshot.editableRevisionId, revision);
  });

  test('9 PATCH no crea post nuevo', () async {
    final gateway = FakePostGateway(
      detailById: {
        63: draftPostDetail(
          id: 63,
          groupId: 2,
          categoryId: 2,
          title: 'X',
          body: 'Y',
        ),
      },
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);
    await c.read(editPostControllerProvider(63).future);
    await c
        .read(editPostControllerProvider(63).notifier)
        .save(categoryId: 2, title: 'X', body: 'Z');
    expect(gateway.createPostCallCount, 0);
    expect(gateway.updatePostCallCount, 1);
  });

  test('10 validación 422 en PATCH', () async {
    final gateway = FakePostGateway(
      detailById: {
        64: draftPostDetail(
          id: 64,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
      updateFailureByPostId: {
        64: const ApiValidationFailure({
          'title': ['inválido'],
        }),
      },
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);
    await c.read(editPostControllerProvider(64).future);
    final result = await c
        .read(editPostControllerProvider(64).notifier)
        .save(categoryId: 2, title: 'T', body: 'B');
    expect(result, isA<EditPostSaveFailure>());
  });

  test('11 error 401', () async {
    final gateway = FakePostGateway(
      detailById: {
        65: draftPostDetail(
          id: 65,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
      updateFailureByPostId: {65: const ApiSessionExpiredFailure()},
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);
    await c.read(editPostControllerProvider(65).future);
    final result = await c
        .read(editPostControllerProvider(65).notifier)
        .save(categoryId: 2, title: 'T', body: 'B');
    expect(result, isA<EditPostSaveFailure>());
    expect(
      (result as EditPostSaveFailure).failure,
      isA<ApiSessionExpiredFailure>(),
    );
  });

  test('12 error 403', () async {
    final gateway = FakePostGateway(
      detailById: {
        66: draftPostDetail(
          id: 66,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
      updateFailureByPostId: {66: const ApiForbiddenFailure()},
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);
    await c.read(editPostControllerProvider(66).future);
    final result = await c
        .read(editPostControllerProvider(66).notifier)
        .save(categoryId: 2, title: 'T', body: 'B');
    expect(result, isA<EditPostSaveFailure>());
  });

  test('13 error 404 en GET', () async {
    final gateway = FakePostGateway(
      detailFailureById: {67: const ApiNotFoundFailure()},
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);
    final sub = c.listen(editPostControllerProvider(67), (_, __) {});
    await expectLater(
      c.read(editPostControllerProvider(67).future),
      throwsA(isA<ApiNotFoundFailure>()),
    );
    sub.close();
  });

  test('14 doble guardar bloqueado', () async {
    final gateway = FakePostGateway(
      detailById: {
        68: draftPostDetail(
          id: 68,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
      updateDelayMs: 100,
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);
    await c.read(editPostControllerProvider(68).future);
    final notifier = c.read(editPostControllerProvider(68).notifier);
    final first = notifier.save(categoryId: 2, title: 'A', body: 'B');
    final second = notifier.save(categoryId: 2, title: 'C', body: 'D');
    await first;
    final r2 = await second;
    expect(r2, isA<EditPostSaveInFlight>());
    expect(gateway.updatePostCallCount, 1);
  });

  test('15 logout durante GET descarta', () async {
    final gateway = FakePostGateway(
      detailDelayMs: 80,
      detailById: {
        69: draftPostDetail(
          id: 69,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);
    final load = c.read(editPostControllerProvider(69).future);
    await c.read(authControllerProvider.notifier).logout(localOnly: true);
    await expectLater(load, throwsA(isA<StateError>()));
  });

  test('16 logout durante PATCH descarta', () async {
    final gateway = FakePostGateway(
      detailById: {
        70: draftPostDetail(
          id: 70,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
      updateDelayMs: 80,
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);
    await c.read(editPostControllerProvider(70).future);
    final op = c
        .read(editPostControllerProvider(70).notifier)
        .save(categoryId: 2, title: 'N', body: 'N');
    await c.read(authControllerProvider.notifier).logout(localOnly: true);
    final result = await op;
    expect(result, isA<EditPostSaveDiscarded>());
  });

  test('17 respuesta tardía de sesión anterior', () async {
    final gateway = FakePostGateway(
      detailById: {
        71: draftPostDetail(
          id: 71,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
      updateDelayMs: 120,
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);
    await c.read(editPostControllerProvider(71).future);

    final op = c
        .read(editPostControllerProvider(71).notifier)
        .save(categoryId: 2, title: 'L', body: 'L');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await c.read(authControllerProvider.notifier).logout(localOnly: true);
    final result = await op;
    expect(result, isA<EditPostSaveDiscarded>());
  });

  test('18 PATCH incierto', () async {
    final gateway = FakePostGateway(
      detailById: {
        72: draftPostDetail(
          id: 72,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
      updateFailureByPostId: {72: const ApiNetworkFailure()},
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);
    await c.read(editPostControllerProvider(72).future);
    final result = await c
        .read(editPostControllerProvider(72).notifier)
        .save(categoryId: 2, title: 'I', body: 'I');
    expect(result, isA<EditPostSaveUncertain>());
    expect(
      c.read(editPostControllerProvider(72)).requireValue.patchUncertain,
      isTrue,
    );
  });

  test('19 reconciliación observable sin confirmar PATCH', () async {
    final gateway = FakePostGateway(
      detailById: {
        73: draftPostDetail(
          id: 73,
          groupId: 2,
          categoryId: 2,
          title: 'Old',
          body: 'Old',
        ),
      },
      updateFailureByPostId: {73: const ApiNetworkFailure()},
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);
    await c.read(editPostControllerProvider(73).future);
    final notifier = c.read(editPostControllerProvider(73).notifier);
    await notifier.save(categoryId: 2, title: 'Match', body: 'Body');
    gateway.updateFailureByPostId!.remove(73);
    gateway.detailById![73] = draftPostDetail(
      id: 73,
      groupId: 2,
      categoryId: 2,
      title: 'Match',
      body: 'Body',
    );
    final reconcile = await notifier.reconcileUncertainPatch();
    expect(reconcile, isA<EditPostReconcileObservableMatch>());
    expect(
      c.read(editPostControllerProvider(73)).requireValue.patchUncertain,
      isTrue,
    );
  });

  test('20 sin reintento automático con incierto', () async {
    final gateway = FakePostGateway(
      detailById: {
        74: draftPostDetail(
          id: 74,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
      updateFailureByPostId: {74: const ApiNetworkFailure()},
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);
    await c.read(editPostControllerProvider(74).future);
    final notifier = c.read(editPostControllerProvider(74).notifier);
    await notifier.save(categoryId: 2, title: 'U', body: 'U');
    final blocked = await notifier.save(categoryId: 2, title: 'U2', body: 'U2');
    expect(blocked, isA<EditPostSaveBlocked>());
    expect(gateway.updatePostCallCount, 1);
  });

  test('21 cambio remoto a pending bloquea', () async {
    final gateway = FakePostGateway(
      detailById: {
        75: draftPostDetail(
          id: 75,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);
    await c.read(editPostControllerProvider(75).future);
    gateway.detailById![75] = pendingPostDetail(id: 75);
    await c.read(editPostControllerProvider(75).notifier).reload();
    final session = c.read(editPostControllerProvider(75)).requireValue;
    expect(session.snapshot.editable, isFalse);
  });

  test('22 cambio remoto a published bloquea', () async {
    final gateway = FakePostGateway(
      detailById: {
        76: draftPostDetail(
          id: 76,
          groupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        ),
      },
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);
    await c.read(editPostControllerProvider(76).future);
    gateway.detailById![76] = sampleCommunityPostDetail(id: 76);
    await c.read(editPostControllerProvider(76).notifier).reload();
    expect(
      c.read(editPostControllerProvider(76)).requireValue.snapshot.editable,
      isFalse,
    );
  });

  test('25 no contaminación entre dos postId', () async {
    final gateway = FakePostGateway(
      detailById: {
        80: draftPostDetail(
          id: 80,
          groupId: 2,
          categoryId: 2,
          title: 'A',
          body: 'A',
        ),
        81: draftPostDetail(
          id: 81,
          groupId: 2,
          categoryId: 2,
          title: 'B',
          body: 'B',
        ),
      },
    );
    final c = buildContainer(gateway);
    addTearDown(c.dispose);
    await c.read(editPostControllerProvider(80).future);
    await c.read(editPostControllerProvider(81).future);
    await c
        .read(editPostControllerProvider(80).notifier)
        .save(categoryId: 2, title: 'A2', body: 'A2');
    final a = c.read(editPostControllerProvider(80)).requireValue;
    final b = c.read(editPostControllerProvider(81)).requireValue;
    expect(a.snapshot.detail.workingContent!.title, 'A2');
    expect(b.snapshot.detail.workingContent!.title, 'B');
  });
}
