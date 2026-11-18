import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/data/models/auth_user.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/posts/application/edit_post_controller.dart';
import 'package:red_vecinal/features/posts/application/edit_post_uncertain_patch_persistence.dart';
import 'package:red_vecinal/features/posts/application/edit_post_uncertain_patch_record.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

class MutableUserAuthController extends AuthController {
  AuthUser _user = sampleAuthUser(id: 1);

  @override
  AuthState build() => AuthAuthenticated(_user);

  void setUser(AuthUser user) {
    _user = user;
    ref.invalidateSelf();
  }
}

void main() {
  ProviderContainer buildContainer(
    FakePostGateway gateway, {
    AuthController Function()? authFactory,
  }) {
    final c = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        postRepositoryProvider.overrideWithValue(gateway),
        authControllerProvider.overrideWith(
          authFactory ?? AuthenticatedBootAuthController.new,
        ),
      ],
    );
    c.read(editPostUncertainPatchPersistenceProvider);
    return c;
  }

  group('4C.2B.5 P2', () {
    test('P2-02 discard tras PATCH promueve outcomeUncertain', () async {
      final gateway = FakePostGateway(
        detailById: {
          401: draftPostDetail(
            id: 401,
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
      final sub = c.listen(editPostControllerProvider(401), (_, __) {});
      addTearDown(sub.close);
      await c.read(editPostControllerProvider(401).future);
      final notifier = c.read(editPostControllerProvider(401).notifier);
      final op = notifier.save(categoryId: 2, title: 'D', body: 'D');
      notifier.debugInvalidateActiveSaveEpoch();
      final result = await op;
      expect(result, isA<EditPostSaveDiscarded>());
      final record = c
          .read(editPostUncertainPatchPersistenceProvider)
          .recordForPost(401);
      expect(record?.phase, EditPostUncertainPatchPhase.outcomeUncertain);
      expect(
        c.read(editPostControllerProvider(401)).requireValue.patchUncertain,
        isTrue,
      );
    });

    test('P2-03 reconcile GET pending conserva incertidumbre', () async {
      final gateway = FakePostGateway(
        detailById: {
          402: draftPostDetail(
            id: 402,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        updateFailureByPostId: {402: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(402).future);
      final notifier = c.read(editPostControllerProvider(402).notifier);
      await notifier.save(categoryId: 2, title: 'P', body: 'P');
      gateway.detailById![402] = pendingPostDetail(id: 402);
      final result = await notifier.reconcileUncertainPatch();
      expect(result, isA<EditPostReconcileRemoteChanged>());
      final msg = (result as EditPostReconcileRemoteChanged).message;
      expect(msg, contains('No confirmamos por HTTP'));
      expect(
        c.read(editPostControllerProvider(402)).requireValue.patchUncertain,
        isTrue,
      );
      expect(
        c.read(editPostUncertainPatchPersistenceProvider).recordForPost(402),
        isNotNull,
      );
    });

    test('P2-03 reconcile GET published conserva incertidumbre', () async {
      final gateway = FakePostGateway(
        detailById: {
          403: draftPostDetail(
            id: 403,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        updateFailureByPostId: {403: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(403).future);
      final notifier = c.read(editPostControllerProvider(403).notifier);
      await notifier.save(categoryId: 2, title: 'Pub', body: 'Pub');
      gateway.detailById![403] = sampleCommunityPostDetail(id: 403);
      final result = await notifier.reconcileUncertainPatch();
      expect(result, isA<EditPostReconcileRemoteChanged>());
      expect(
        c.read(editPostControllerProvider(403)).requireValue.patchUncertain,
        isTrue,
      );
    });

    test('P2-05 GET 404 en reconciliación', () async {
      final gateway = FakePostGateway(
        detailById: {
          404: draftPostDetail(
            id: 404,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        updateFailureByPostId: {404: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(404).future);
      final notifier = c.read(editPostControllerProvider(404).notifier);
      await notifier.save(categoryId: 2, title: 'X', body: 'X');
      gateway.detailFailureById = {404: const ApiNotFoundFailure()};
      final result = await notifier.reconcileUncertainPatch();
      expect(result, isA<EditPostReconcileStillUncertain>());
      expect(notifier.lastReconcileObservation, isNull);
    });

    test('P2-05 GET timeout en reconciliación', () async {
      final gateway = FakePostGateway(
        detailById: {
          405: draftPostDetail(
            id: 405,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        updateFailureByPostId: {405: const ApiNetworkFailure()},
      );
      final c = buildContainer(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(405).future);
      final notifier = c.read(editPostControllerProvider(405).notifier);
      await notifier.save(categoryId: 2, title: 'T', body: 'T');
      gateway.detailFailureById = {405: const ApiTimeoutFailure()};
      final result = await notifier.reconcileUncertainPatch();
      expect(result, isA<EditPostReconcileStillUncertain>());
    });

    test('P2-05 cambio de usuario aísla persistencia', () async {
      final gateway = FakePostGateway(
        detailById: {
          406: draftPostDetail(
            id: 406,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        updateFailureByPostId: {406: const ApiNetworkFailure()},
      );
      final c = buildContainer(
        gateway,
        authFactory: MutableUserAuthController.new,
      );
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(406).future);
      await c
          .read(editPostControllerProvider(406).notifier)
          .save(categoryId: 2, title: 'U1', body: 'U1');
      expect(
        c.read(editPostUncertainPatchPersistenceProvider).recordForPost(406),
        isNotNull,
      );
      (c.read(authControllerProvider.notifier) as MutableUserAuthController)
          .setUser(sampleAuthUser(id: 2, email: 'otro@test.com'));
      expect(
        c.read(editPostUncertainPatchPersistenceProvider).recordForPost(406),
        isNull,
      );
    });

    test('P2-05 inFlight vs outcomeUncertain al restaurar', () async {
      final gateway = FakePostGateway(
        detailById: {
          407: draftPostDetail(
            id: 407,
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
      await c.read(editPostControllerProvider(407).future);
      final notifier = c.read(editPostControllerProvider(407).notifier);
      final op = notifier.save(categoryId: 2, title: 'Fly', body: 'Fly');
      expect(
        c
            .read(editPostUncertainPatchPersistenceProvider)
            .recordForPost(407)!
            .phase,
        EditPostUncertainPatchPhase.inFlight,
      );
      c.invalidate(editPostControllerProvider(407));
      final session = await c.read(editPostControllerProvider(407).future);
      expect(session.uncertainPhase, EditPostUncertainPatchPhase.inFlight);
      await op;
      c.invalidate(editPostControllerProvider(407));
      final afterSuccess = await c.read(editPostControllerProvider(407).future);
      expect(afterSuccess.patchUncertain, isFalse);
      expect(afterSuccess.uncertainPhase, isNull);

      gateway.updateFailureByPostId = {407: const ApiNetworkFailure()};
      await c
          .read(editPostControllerProvider(407).notifier)
          .save(categoryId: 2, title: 'Unc', body: 'Unc');
      c.invalidate(editPostControllerProvider(407));
      final afterUncertain = await c.read(
        editPostControllerProvider(407).future,
      );
      expect(afterUncertain.patchUncertain, isTrue);
      expect(
        afterUncertain.uncertainPhase,
        EditPostUncertainPatchPhase.outcomeUncertain,
      );
    });
  });
}
