import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/data/models/auth_user.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/posts/application/edit_post_attachments_controller.dart';
import 'package:red_vecinal/features/posts/application/edit_post_attachments_persistence.dart';
import 'package:red_vecinal/features/posts/application/edit_post_controller.dart';
import 'package:red_vecinal/features/posts/application/edit_post_exclusive_operation.dart';
import 'package:red_vecinal/features/posts/application/edit_post_uncertain_submit_persistence.dart';
import 'package:red_vecinal/features/posts/application/my_posts_controller.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

class MutableUserAuthController extends AuthController {
  MutableUserAuthController({AuthUser? initial})
    : _user = initial ?? sampleAuthUser(id: 1);

  AuthUser _user;

  @override
  AuthState build() => AuthAuthenticated(_user);

  Future<void> rotateSession(AuthUser user) async {
    await logout(localOnly: true);
    _user = user;
    state = AuthAuthenticated(_user);
    ref.invalidateSelf();
  }
}

void main() {
  ProviderContainer buildContainer(
    FakePostGateway gateway, {
    AuthController Function()? authFactory,
  }) {
    final container = ProviderContainer(
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
    container.read(editPostAttachmentsPersistenceProvider);
    container.read(editPostUncertainSubmitPersistenceProvider);
    return container;
  }

  void keepAlive(ProviderContainer c, int postId) {
    c.listen(editPostControllerProvider(postId), (_, __) {});
    c.listen(editPostAttachmentsControllerProvider(postId), (_, __) {});
  }

  Future<void> hydrate(ProviderContainer c, FakePostGateway g, int id) async {
    await c.read(editPostControllerProvider(id).future);
    keepAlive(c, id);
    final rev = g.detailById![id]!.editableRevisionId!;
    c
        .read(editPostAttachmentsControllerProvider(id).notifier)
        .hydrateFromEditableRevision(
          revisionId: rev,
          serverAttachments: [],
          editorLoadGeneration: 1,
        );
  }

  Future<EditPostSubmitResult> submit(
    ProviderContainer c,
    int id, {
    String title = 'T',
    String body = 'B',
  }) {
    return c
        .read(editPostControllerProvider(id).notifier)
        .submitToModeration(categoryId: 2, title: title, body: body);
  }

  group('4C.2G submit sesión adversarial', () {
    test('P2-1 logout durante submit descarta sin pending falso', () async {
      final g = FakePostGateway(
        detailById: {
          1501: draftPostDetail(
            id: 1501,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        submitPostDelayMs: 120,
        myPostsPage: const PaginatedFeedPosts(
          items: [],
          currentPage: 1,
          lastPage: 1,
        ),
      );
      final c = buildContainer(g);
      addTearDown(c.dispose);
      c.listen(myPostsControllerProvider, (_, __) {});
      await c.read(myPostsControllerProvider.future);
      final myPostsBefore = g.listMyPostsCallCount;
      await hydrate(c, g, 1501);
      final op = submit(c, 1501);
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await c.read(authControllerProvider.notifier).logout(localOnly: true);
      expect(await op, isA<EditPostSubmitDiscarded>());
      expect(g.submitPostCallCount, 1);
      expect(g.listMyPostsCallCount, myPostsBefore);
      final persistence = c.read(
        editPostAttachmentsPersistenceProvider.notifier,
      );
      expect(persistence.exclusiveKindForPost(1501), isNull);
    });

    test(
      'P2-1 logout: nueva sesión no queda bloqueada por lock antiguo',
      () async {
        final auth = MutableUserAuthController();
        final g = FakePostGateway(
          detailById: {
            1502: draftPostDetail(
              id: 1502,
              groupId: 2,
              categoryId: 2,
              title: 'T',
              body: 'B',
            ),
          },
          submitPostDelayMs: 100,
        );
        final c = buildContainer(g, authFactory: () => auth);
        addTearDown(c.dispose);
        await hydrate(c, g, 1502);
        final first = submit(c, 1502);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await auth.rotateSession(
          sampleAuthUser(id: 99, email: 'nuevo@test.com'),
        );
        expect(await first, isA<EditPostSubmitDiscarded>());
        await c.read(editPostControllerProvider(1502).future);
        final second = await submit(c, 1502);
        expect(second, isA<EditPostSubmitSuccess>());
        expect(g.submitPostCallCount, 2);
      },
    );

    test('P2-1 cambio de usuario: submit A no afecta B', () async {
      final auth = MutableUserAuthController();
      final g = FakePostGateway(
        detailById: {
          1503: draftPostDetail(
            id: 1503,
            groupId: 2,
            categoryId: 2,
            title: 'A',
            body: 'A',
          ),
          1504: draftPostDetail(
            id: 1504,
            groupId: 2,
            categoryId: 2,
            title: 'B',
            body: 'B',
          ),
        },
        submitPostDelayMs: 120,
        myPostsPage: const PaginatedFeedPosts(
          items: [],
          currentPage: 1,
          lastPage: 1,
        ),
      );
      final c = buildContainer(g, authFactory: () => auth);
      addTearDown(c.dispose);
      c.listen(myPostsControllerProvider, (_, __) {});
      await c.read(myPostsControllerProvider.future);
      await hydrate(c, g, 1503);
      final opA = submit(c, 1503, title: 'A', body: 'A');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      await auth.rotateSession(sampleAuthUser(id: 2, email: 'b@test.com'));
      final opAResult = await opA;
      expect(opAResult, isNot(isA<EditPostSubmitSuccess>()));
      final afterOpAListCalls = g.listMyPostsCallCount;
      await hydrate(c, g, 1504);
      expect(
        c
            .read(editPostControllerProvider(1504))
            .requireValue
            .snapshot
            .detail
            .status,
        'draft',
      );
      final bSubmit = await submit(c, 1504, title: 'B', body: 'B');
      expect(bSubmit, isA<EditPostSubmitSuccess>());
      c.invalidate(myPostsControllerProvider);
      await c.read(postRepositoryProvider).listMyPosts();
      expect(g.listMyPostsCallCount, greaterThan(afterOpAListCalls));
      expect(g.submitPostCallCount, 2);
    });

    test(
      'P2-1 respuesta 200 tardía tras logout no declara pending local',
      () async {
        final auth = MutableUserAuthController();
        final g = FakePostGateway(
          detailById: {
            1505: draftPostDetail(
              id: 1505,
              groupId: 2,
              categoryId: 2,
              title: 'T',
              body: 'B',
            ),
          },
          submitPostDelayMs: 80,
        );
        final c = buildContainer(g, authFactory: () => auth);
        addTearDown(c.dispose);
        await hydrate(c, g, 1505);
        final op = submit(c, 1505);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await auth.rotateSession(sampleAuthUser(id: 3));
        expect(await op, isA<EditPostSubmitDiscarded>());
        await c.read(editPostControllerProvider(1505).future);
        final session = c.read(editPostControllerProvider(1505)).valueOrNull;
        if (session != null) {
          expect(session.snapshot.detail.status, isNot('pending'));
        }
        expect(
          c
              .read(editPostUncertainSubmitPersistenceProvider)
              .recordForPost(1505),
          isNull,
        );
      },
    );

    test(
      'P2-1 respuesta 200 tardía tras cambio de usuario no invalida B',
      () async {
        final auth = MutableUserAuthController();
        final g = FakePostGateway(
          detailById: {
            1506: draftPostDetail(
              id: 1506,
              groupId: 2,
              categoryId: 2,
              title: 'T',
              body: 'B',
            ),
          },
          submitPostDelayMs: 100,
          myPostsPage: const PaginatedFeedPosts(
            items: [],
            currentPage: 1,
            lastPage: 1,
          ),
        );
        final c = buildContainer(g, authFactory: () => auth);
        addTearDown(c.dispose);
        c.listen(myPostsControllerProvider, (_, __) {});
        await c.read(myPostsControllerProvider.future);
        await hydrate(c, g, 1506);
        final op = submit(c, 1506);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        await auth.rotateSession(sampleAuthUser(id: 4));
        final afterRotate = g.listMyPostsCallCount;
        final opResult = await op;
        expect(opResult, isNot(isA<EditPostSubmitSuccess>()));
        expect(g.listMyPostsCallCount, lessThanOrEqualTo(afterRotate + 1));
      },
    );

    test('P2-1 respuesta 500 tardía tras cambio de sesión', () async {
      final auth = MutableUserAuthController();
      final g = FakePostGateway(
        detailById: {
          1507: draftPostDetail(
            id: 1507,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        submitPostDelayMs: 60,
        submitFailureByPostId: {1507: const ApiServerFailure()},
      );
      final c = buildContainer(g, authFactory: () => auth);
      addTearDown(c.dispose);
      await hydrate(c, g, 1507);
      final op = submit(c, 1507);
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await auth.rotateSession(sampleAuthUser(id: 5));
      expect(await op, isA<EditPostSubmitDiscarded>());
      expect(
        c.read(editPostUncertainSubmitPersistenceProvider).recordForPost(1507),
        isNull,
      );
    });

    test('P2-1 reload reciente: submit tardío descartado', () async {
      final g = FakePostGateway(
        detailById: {
          1508: draftPostDetail(
            id: 1508,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        submitPostDelayMs: 100,
      );
      final c = buildContainer(g);
      addTearDown(c.dispose);
      await hydrate(c, g, 1508);
      final notifier = c.read(editPostControllerProvider(1508).notifier);
      final op = submit(c, 1508);
      await notifier.reload();
      expect(await op, isA<EditPostSubmitDiscarded>());
      final session = c.read(editPostControllerProvider(1508)).requireValue;
      expect(session.snapshot.detail.status, 'draft');
      expect(session.snapshot.editable, isTrue);
    });

    test('P2-1 lease antiguo submit no libera reserva nueva', () {
      final g = FakePostGateway(
        detailById: {
          1509: draftPostDetail(
            id: 1509,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
      );
      final c = buildContainer(g);
      addTearDown(c.dispose);
      final persistence = c.read(
        editPostAttachmentsPersistenceProvider.notifier,
      );
      final auth = c.read(authControllerProvider) as AuthAuthenticated;
      final userId = auth.user.id;
      final epoch = c.read(authControllerProvider.notifier).sessionEpoch;
      final leaseA = persistence.tryAcquireExclusive(
        userId: userId,
        sessionEpoch: epoch,
        postId: 1509,
        kind: EditPostExclusiveOperationKind.submit,
      );
      expect(leaseA, isNotNull);
      persistence.releaseExclusive(leaseA!);
      final leaseB = persistence.tryAcquireExclusive(
        userId: userId,
        sessionEpoch: epoch,
        postId: 1509,
        kind: EditPostExclusiveOperationKind.submit,
      );
      expect(leaseB, isNotNull);
      expect(persistence.releaseExclusive(leaseA), isFalse);
      expect(
        persistence.exclusiveKindForPost(1509),
        EditPostExclusiveOperationKind.submit,
      );
      persistence.releaseExclusive(leaseB!);
    });
  });
}
