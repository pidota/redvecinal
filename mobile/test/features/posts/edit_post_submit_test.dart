import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/application/create_post_controller.dart';
import 'package:red_vecinal/features/posts/application/create_post_file_picker.dart';
import 'package:red_vecinal/features/posts/application/create_post_local_attachment.dart';
import 'package:red_vecinal/features/posts/application/edit_post_attachments_controller.dart';
import 'package:red_vecinal/features/posts/application/my_posts_controller.dart';
import 'package:red_vecinal/features/posts/application/edit_post_attachments_persistence.dart';
import 'package:red_vecinal/features/posts/application/edit_post_controller.dart';
import 'package:red_vecinal/features/posts/application/edit_post_uncertain_submit_persistence.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'create_post_attachments_flow_test.dart';
import 'post_test_support.dart';

void main() {
  late PickedPostFile pick;

  setUpAll(() async {
    final f = File('test/fixtures/tiny_upload.pdf');
    pick = PickedPostFile(
      path: f.path,
      displayName: 'tiny_upload.pdf',
      sizeBytes: await f.length(),
      mimeType: 'application/pdf',
    );
  });

  ProviderContainer c(
    FakePostGateway gateway, {
    AuthController Function()? auth,
  }) {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        postRepositoryProvider.overrideWithValue(gateway),
        createPostFilePickerProvider.overrideWithValue(
          FakeCreatePostFilePicker(pick),
        ),
        authControllerProvider.overrideWith(
          auth ?? AuthenticatedBootAuthController.new,
        ),
      ],
    );
    container.read(editPostAttachmentsPersistenceProvider);
    container.read(editPostUncertainSubmitPersistenceProvider);
    return container;
  }

  void alive(ProviderContainer container, int id) {
    container.listen(editPostControllerProvider(id), (_, __) {});
    container.listen(editPostAttachmentsControllerProvider(id), (_, __) {});
  }

  Future<void> hydrateSaved(
    ProviderContainer container,
    FakePostGateway gateway,
    int id, {
    String title = 'T',
    String body = 'B',
  }) async {
    await container.read(editPostControllerProvider(id).future);
    alive(container, id);
    container
        .read(editPostAttachmentsControllerProvider(id).notifier)
        .hydrateFromEditableRevision(
          revisionId: gateway.detailById![id]!.editableRevisionId!,
          serverAttachments: [],
          editorLoadGeneration: 1,
        );
  }

  Future<EditPostSubmitResult> submitDefault(
    ProviderContainer container,
    int id, {
    String title = 'T',
    String body = 'B',
  }) {
    return container
        .read(editPostControllerProvider(id).notifier)
        .submitToModeration(categoryId: 2, title: title, body: body);
  }

  group('4C.2E submit moderación', () {
    test('1 draft exitoso → pending', () async {
      final g = FakePostGateway(
        detailById: {
          1101: draftPostDetail(
            id: 1101,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
      );
      final container = c(g);
      addTearDown(container.dispose);
      await hydrateSaved(container, g, 1101);
      expect(
        await submitDefault(container, 1101),
        isA<EditPostSubmitSuccess>(),
      );
      expect(g.submitPostCallCount, 1);
      expect(
        container
            .read(editPostControllerProvider(1101))
            .value!
            .snapshot
            .detail
            .status,
        'pending',
      );
    });

    test('2 rejected exitoso', () async {
      final g = FakePostGateway(
        detailById: {
          1102: rejectedPostDetail(
            id: 1102,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
      );
      final container = c(g);
      addTearDown(container.dispose);
      await hydrateSaved(container, g, 1102);
      expect(
        await submitDefault(container, 1102),
        isA<EditPostSubmitSuccess>(),
      );
    });

    test('3 sin guardar bloquea', () async {
      final g = FakePostGateway(
        detailById: {
          1103: draftPostDetail(
            id: 1103,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
      );
      final container = c(g);
      addTearDown(container.dispose);
      await hydrateSaved(container, g, 1103);
      final r = await submitDefault(container, 1103, title: 'Otro', body: 'B');
      expect(r, isA<EditPostSubmitBlocked>());
      expect(g.submitPostCallCount, 0);
    });

    test('4 adjuntos locales pendientes', () async {
      final g = FakePostGateway(
        detailById: {
          1104: draftPostDetail(
            id: 1104,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
      );
      final container = c(g);
      addTearDown(container.dispose);
      await hydrateSaved(container, g, 1104);
      await container
          .read(editPostAttachmentsControllerProvider(1104).notifier)
          .pickAndAddPdf();
      expect(
        await submitDefault(container, 1104),
        isA<EditPostSubmitBlocked>(),
      );
    });

    test('5 PATCH activo bloquea', () async {
      final g = FakePostGateway(
        detailById: {
          1105: draftPostDetail(
            id: 1105,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        updateDelayMs: 100,
      );
      final container = c(g);
      addTearDown(container.dispose);
      await hydrateSaved(container, g, 1105);
      final edit = container.read(editPostControllerProvider(1105).notifier);
      final patch = edit.save(categoryId: 2, title: 'T', body: 'B');
      expect(
        await submitDefault(container, 1105),
        isA<EditPostSubmitBlocked>(),
      );
      await patch;
    });

    test('7 upload activo bloquea', () async {
      final g = FakePostGateway(
        detailById: {
          1107: draftPostDetail(
            id: 1107,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        uploadDelayMs: 120,
      );
      final container = c(g);
      addTearDown(container.dispose);
      await hydrateSaved(container, g, 1107);
      final attach = container.read(
        editPostAttachmentsControllerProvider(1107).notifier,
      );
      attach.setLocalItemsForTests([
        CreatePostLocalAttachment(
          clientId: 'u1',
          path: pick.path,
          displayName: 'u1.pdf',
          sizeBytes: pick.sizeBytes,
          mimeType: pick.mimeType,
        ),
      ]);
      final uploadFuture = attach.uploadPending();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(
        await submitDefault(container, 1107),
        isA<EditPostSubmitBlocked>(),
      );
      await uploadFuture;
      expect(g.submitPostCallCount, 0);
    });

    test('8 upload incierto bloquea', () async {
      final g = FakePostGateway(
        detailById: {
          1108: draftPostDetail(
            id: 1108,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        uploadFailureByPostId: {1108: const ApiNetworkFailure()},
      );
      final container = c(g);
      addTearDown(container.dispose);
      await hydrateSaved(container, g, 1108);
      final attach = container.read(
        editPostAttachmentsControllerProvider(1108).notifier,
      );
      await attach.pickAndAddPdf();
      await attach.uploadPending();
      expect(
        await submitDefault(container, 1108),
        isA<EditPostSubmitBlocked>(),
      );
      expect(g.submitPostCallCount, 0);
    });

    test('6 PATCH incierto bloquea', () async {
      final g = FakePostGateway(
        detailById: {
          1106: draftPostDetail(
            id: 1106,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        updateFailureByPostId: {1106: const ApiNetworkFailure()},
      );
      final container = c(g);
      addTearDown(container.dispose);
      await hydrateSaved(container, g, 1106);
      await container
          .read(editPostControllerProvider(1106).notifier)
          .save(categoryId: 2, title: 'T', body: 'B');
      expect(
        await submitDefault(container, 1106),
        isA<EditPostSubmitBlocked>(),
      );
    });

    test('9 dos submit simultáneos: un HTTP', () async {
      final g = FakePostGateway(
        detailById: {
          1109: draftPostDetail(
            id: 1109,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        submitPostDelayMs: 80,
      );
      final container = c(g);
      addTearDown(container.dispose);
      await hydrateSaved(container, g, 1109);
      final results = await Future.wait([
        submitDefault(container, 1109),
        submitDefault(container, 1109),
      ]);
      expect(g.submitPostCallCount, 1);
      expect(results.whereType<EditPostSubmitSuccess>().length, 1);
    });

    test('11 submit y upload simultáneos', () async {
      final g = FakePostGateway(
        detailById: {
          1111: draftPostDetail(
            id: 1111,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        uploadDelayMs: 80,
        submitPostDelayMs: 80,
      );
      final container = c(g);
      addTearDown(container.dispose);
      await hydrateSaved(container, g, 1111);
      final attach = container.read(
        editPostAttachmentsControllerProvider(1111).notifier,
      );
      attach.setLocalItemsForTests([
        CreatePostLocalAttachment(
          clientId: 'u2',
          path: pick.path,
          displayName: 'u2.pdf',
          sizeBytes: pick.sizeBytes,
          mimeType: pick.mimeType,
        ),
      ]);
      final results = await Future.wait([
        submitDefault(container, 1111),
        attach.uploadPending(),
      ]);
      expect(g.submitPostCallCount + g.uploadCallCount, 1);
      expect(
        results.where(
          (r) => r is EditPostSubmitBlocked || r is EditPostUploadBlocked,
        ).length,
        1,
      );
    });

    test('10 submit y PATCH simultáneos', () async {
      final g = FakePostGateway(
        detailById: {
          1110: draftPostDetail(
            id: 1110,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        updateDelayMs: 80,
        submitPostDelayMs: 80,
      );
      final container = c(g);
      addTearDown(container.dispose);
      await hydrateSaved(container, g, 1110);
      final edit = container.read(editPostControllerProvider(1110).notifier);
      final results = await Future.wait([
        submitDefault(container, 1110),
        edit.save(categoryId: 2, title: 'T', body: 'B'),
      ]);
      expect(g.submitPostCallCount + g.updatePostCallCount, 1);
      expect(
        results
            .where(
              (r) => r is EditPostSubmitBlocked || r is EditPostSaveBlocked,
            )
            .length,
        1,
      );
    });

    test('20 timeout → incierto sin reintento', () async {
      final g = FakePostGateway(
        detailById: {
          1120: draftPostDetail(
            id: 1120,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        submitThrowsUncertain: true,
      );
      final container = c(g);
      addTearDown(container.dispose);
      await hydrateSaved(container, g, 1120);
      expect(
        await submitDefault(container, 1120),
        isA<EditPostSubmitUncertain>(),
      );
      expect(g.submitPostCallCount, 1);
      expect(
        await submitDefault(container, 1120),
        isA<EditPostSubmitBlocked>(),
      );
    });

    test('24 persistencia tras remount', () async {
      final g = FakePostGateway(
        detailById: {
          1124: draftPostDetail(
            id: 1124,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        submitThrowsUncertain: true,
      );
      final container = c(g);
      addTearDown(container.dispose);
      await hydrateSaved(container, g, 1124);
      await submitDefault(container, 1124);
      container.invalidate(editPostControllerProvider(1124));
      final session =
          container.read(editPostControllerProvider(1124)).requireValue;
      expect(session.submitUncertain, isTrue);
    });

    test('25 GET pending tras incertidumbre', () async {
      final g = FakePostGateway(
        detailById: {
          1125: draftPostDetail(
            id: 1125,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        submitThrowsUncertain: true,
      );
      final container = c(g);
      addTearDown(container.dispose);
      await hydrateSaved(container, g, 1125);
      await submitDefault(container, 1125);
      g.detailById![1125] = pendingPostDetail(id: 1125);
      final r =
          await container
              .read(editPostControllerProvider(1125).notifier)
              .reconcileUncertainSubmit();
      expect(r, isA<EditPostSubmitReconcileObservedPending>());
    });

    test('26 GET draft tras incertidumbre', () async {
      final g = FakePostGateway(
        detailById: {
          1126: draftPostDetail(
            id: 1126,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        submitThrowsUncertain: true,
      );
      final container = c(g);
      addTearDown(container.dispose);
      await hydrateSaved(container, g, 1126);
      await submitDefault(container, 1126);
      final r =
          await container
              .read(editPostControllerProvider(1126).notifier)
              .reconcileUncertainSubmit();
      expect(r, isA<EditPostSubmitReconcileStillUncertain>());
      expect(
        container.read(editPostControllerProvider(1126)).value!.submitUncertain,
        isTrue,
      );
    });

    test('27 GET fallido tras incertidumbre', () async {
      final g = FakePostGateway(
        detailById: {
          1127: draftPostDetail(
            id: 1127,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        submitThrowsUncertain: true,
        detailFailureAfterCalls: 1,
      );
      final container = c(g);
      addTearDown(container.dispose);
      await hydrateSaved(container, g, 1127);
      await submitDefault(container, 1127);
      final r =
          await container
              .read(editPostControllerProvider(1127).notifier)
              .reconcileUncertainSubmit();
      expect(r, isA<EditPostSubmitReconcileGetFailed>());
    });

    test('30 invalidate Mis publicaciones tras éxito', () async {
      final g = FakePostGateway(
        detailById: {
          1129: draftPostDetail(
            id: 1129,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        myPostsPage: const PaginatedFeedPosts(
          items: [],
          currentPage: 1,
          lastPage: 1,
        ),
      );
      final container = c(g);
      addTearDown(container.dispose);
      container.listen(myPostsControllerProvider, (_, __) {});
      await container.read(myPostsControllerProvider.future);
      final before = g.listMyPostsCallCount;
      await hydrateSaved(container, g, 1129);
      await submitDefault(container, 1129);
      await container.read(myPostsControllerProvider.future);
      expect(g.listMyPostsCallCount, greaterThan(before));
    });

    test('28–29 sin PATCH ni upload extra', () async {
      final g = FakePostGateway(
        detailById: {
          1128: draftPostDetail(
            id: 1128,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
      );
      final container = c(g);
      addTearDown(container.dispose);
      await hydrateSaved(container, g, 1128);
      await submitDefault(container, 1128);
      expect(g.updatePostCallCount, 0);
      expect(g.uploadCallCount, 0);
    });

    test('35 sin regresión creación', () async {
      final container = c(FakePostGateway());
      addTearDown(container.dispose);
      expect(container.read(createPostControllerProvider), isNotNull);
    });
  });

  group('4C.2E errores submit', () {
    final base = {
      1130: draftPostDetail(
        id: 1130,
        groupId: 2,
        categoryId: 2,
        title: 'T',
        body: 'B',
      ),
    };

    Future<void> runFailure(Object failure, Matcher matcher) async {
      final g = FakePostGateway(
        detailById: base,
        submitFailureByPostId: {1130: failure},
      );
      final container = c(g);
      addTearDown(container.dispose);
      await hydrateSaved(container, g, 1130);
      expect(await submitDefault(container, 1130), matcher);
      expect(g.submitPostCallCount, 1);
    }

    test(
      '15 401',
      () => runFailure(
        const ApiSessionExpiredFailure(),
        isA<EditPostSubmitFailure>(),
      ),
    );
    test(
      '16 403',
      () =>
          runFailure(const ApiForbiddenFailure(), isA<EditPostSubmitFailure>()),
    );
    test(
      '17 404',
      () =>
          runFailure(const ApiNotFoundFailure(), isA<EditPostSubmitFailure>()),
    );
    test(
      '18 409',
      () =>
          runFailure(const ApiConflictFailure(), isA<EditPostSubmitFailure>()),
    );
    test(
      '19 422',
      () => runFailure(
        const ApiValidationFailure({
          'x': ['y'],
        }),
        isA<EditPostSubmitFailure>(),
      ),
    );
    test(
      '21 network',
      () =>
          runFailure(const ApiNetworkFailure(), isA<EditPostSubmitUncertain>()),
    );
    test(
      '22 500',
      () =>
          runFailure(const ApiServerFailure(), isA<EditPostSubmitUncertain>()),
    );
  });
}
