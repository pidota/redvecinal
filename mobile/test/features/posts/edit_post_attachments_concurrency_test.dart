import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/posts/application/edit_post_exclusive_operation.dart';
import 'package:red_vecinal/features/posts/application/create_post_file_picker.dart';
import 'package:red_vecinal/features/posts/application/create_post_local_attachment.dart';
import 'package:red_vecinal/features/posts/application/edit_post_attachments_controller.dart';
import 'package:red_vecinal/features/posts/application/edit_post_attachments_persistence.dart';
import 'package:red_vecinal/features/posts/application/edit_post_controller.dart';
import 'package:red_vecinal/features/posts/application/edit_post_uncertain_patch_persistence.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'create_post_attachments_flow_test.dart';
import 'edit_post_controller_b25_test.dart';
import 'post_test_support.dart';

class DelayedFakeCreatePostFilePicker implements CreatePostFilePickerPort {
  DelayedFakeCreatePostFilePicker(
    this.file, {
    this.delayMs = 80,
    this.onBeforeReturn,
  });

  final PickedPostFile? file;
  final int delayMs;
  final void Function()? onBeforeReturn;

  @override
  Future<PickedPostFile?> pickImage() async {
    await Future<void>.delayed(Duration(milliseconds: delayMs));
    onBeforeReturn?.call();
    return file;
  }

  @override
  Future<PickedPostFile?> pickPdf() async {
    await Future<void>.delayed(Duration(milliseconds: delayMs));
    onBeforeReturn?.call();
    return file;
  }
}

PostDetail postDetailWithRevision({
  required int id,
  required int revisionId,
  List<Map<String, dynamic>> attachments = const [],
}) {
  final json = Map<String, dynamic>.from(sampleCommunityPostJson(id: id));
  json['status'] = 'draft';
  json['content'] = null;
  json['working_content'] = {
    'revision_id': revisionId,
    'title': 'T',
    'body': 'B',
  };
  json['attachments'] = attachments;
  return PostDetail.fromJson(json);
}

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

  void keepAlive(ProviderContainer container, int postId) {
    container.listen(editPostControllerProvider(postId), (_, __) {});
    container.listen(editPostAttachmentsControllerProvider(postId), (_, __) {});
  }

  ProviderContainer buildContainer(
    FakePostGateway gateway, {
    CreatePostFilePickerPort? picker,
    AuthController Function()? authFactory,
  }) {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        postRepositoryProvider.overrideWithValue(gateway),
        createPostFilePickerProvider.overrideWithValue(
          picker ?? FakeCreatePostFilePicker(pick),
        ),
        authControllerProvider.overrideWith(
          authFactory ?? AuthenticatedBootAuthController.new,
        ),
      ],
    );
    container.read(editPostAttachmentsPersistenceProvider);
    container.read(editPostUncertainPatchPersistenceProvider);
    return container;
  }

  Future<void> hydrateDefault(
    ProviderContainer container,
    FakePostGateway gateway,
    int postId,
  ) async {
    await container.read(editPostControllerProvider(postId).future);
    keepAlive(container, postId);
    final snap = EditPostSnapshot.fromDetail(gateway.detailById![postId]!);
    final attachNotifier = container.read(
      editPostAttachmentsControllerProvider(postId).notifier,
    );
    attachNotifier.hydrateFromEditableRevision(
      revisionId: snap.editableRevisionId!,
      serverAttachments: snap.readOnlyAttachments,
      editorLoadGeneration:
          container
              .read(editPostControllerProvider(postId).notifier)
              .editorLoadGeneration,
    );
    await container
        .read(editPostAttachmentsControllerProvider(postId).notifier)
        .pickAndAddPdf();
  }

  group('4C.2D.1 concurrencia PATCH/upload', () {
    test('1 PATCH primero bloquea upload concurrente', () async {
      final gateway = FakePostGateway(
        detailById: {
          951: draftPostDetail(
            id: 951,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        updateDelayMs: 120,
      );
      final container = buildContainer(gateway);
      addTearDown(container.dispose);
      await hydrateDefault(container, gateway, 951);
      final edit = container.read(editPostControllerProvider(951).notifier);
      final attach = container.read(
        editPostAttachmentsControllerProvider(951).notifier,
      );
      final saveFuture = edit.save(categoryId: 2, title: 'N', body: 'N');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final upload = await attach.uploadPending();
      expect(upload, isA<EditPostUploadBlocked>());
      await saveFuture;
      expect(gateway.updatePostCallCount, 1);
      expect(gateway.uploadCallCount, 0);
    });

    test('2 upload primero bloquea PATCH concurrente', () async {
      final gateway = FakePostGateway(
        detailById: {
          952: draftPostDetail(
            id: 952,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        uploadDelayMs: 120,
      );
      final container = buildContainer(gateway);
      addTearDown(container.dispose);
      await hydrateDefault(container, gateway, 952);
      final edit = container.read(editPostControllerProvider(952).notifier);
      final attach = container.read(
        editPostAttachmentsControllerProvider(952).notifier,
      );
      final uploadFuture = attach.uploadPending();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final save = await edit.save(categoryId: 2, title: 'N', body: 'N');
      expect(save, isA<EditPostSaveBlocked>());
      await uploadFuture;
      expect(gateway.uploadCallCount, 1);
      expect(gateway.updatePostCallCount, 0);
    });

    test('3 mismo ciclo: solo una operación HTTP', () async {
      final gateway = FakePostGateway(
        detailById: {
          953: draftPostDetail(
            id: 953,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        updateDelayMs: 80,
        uploadDelayMs: 80,
      );
      final container = buildContainer(gateway);
      addTearDown(container.dispose);
      await hydrateDefault(container, gateway, 953);
      final edit = container.read(editPostControllerProvider(953).notifier);
      final attach = container.read(
        editPostAttachmentsControllerProvider(953).notifier,
      );
      final results = await Future.wait([
        edit.save(categoryId: 2, title: 'N', body: 'N'),
        attach.uploadPending(),
      ]);
      final blocked = results.where(
        (r) => r is EditPostSaveBlocked || r is EditPostUploadBlocked,
      );
      expect(blocked.length, 1);
      expect(gateway.updatePostCallCount + gateway.uploadCallCount, 1);
    });

    test('4 dos uploads simultáneos: uno bloqueado', () async {
      final gateway = FakePostGateway(
        detailById: {
          954: draftPostDetail(
            id: 954,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        uploadDelayMs: 100,
      );
      final container = buildContainer(gateway);
      addTearDown(container.dispose);
      await hydrateDefault(container, gateway, 954);
      final attach = container.read(
        editPostAttachmentsControllerProvider(954).notifier,
      );
      attach.setLocalItemsForTests([
        CreatePostLocalAttachment(
          clientId: 'a',
          path: pick.path,
          displayName: 'a.pdf',
          sizeBytes: pick.sizeBytes,
          mimeType: pick.mimeType,
        ),
      ]);
      final outcomes = await Future.wait([
        attach.uploadPending(),
        attach.uploadPending(),
      ]);
      expect(outcomes.whereType<EditPostUploadBlocked>().length, 1);
      expect(gateway.uploadCallCount, 1);
    });

    test('7 segunda operación tras liberar lock', () async {
      final gateway = FakePostGateway(
        detailById: {
          955: draftPostDetail(
            id: 955,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
      );
      final container = buildContainer(gateway);
      addTearDown(container.dispose);
      await hydrateDefault(container, gateway, 955);
      final edit = container.read(editPostControllerProvider(955).notifier);
      final attach = container.read(
        editPostAttachmentsControllerProvider(955).notifier,
      );
      await edit.save(categoryId: 2, title: 'A', body: 'A');
      final upload = await attach.uploadPending();
      expect(upload, isA<EditPostUploadSuccess>());
      expect(gateway.updatePostCallCount, 1);
      expect(gateway.uploadCallCount, 1);
    });

    test('8 logout durante PATCH descarta sin bloquear sesión nueva', () async {
      final gateway = FakePostGateway(
        detailById: {
          956: draftPostDetail(
            id: 956,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        updateDelayMs: 120,
      );
      final auth = MutableUserAuthController();
      final container = buildContainer(gateway, authFactory: () => auth);
      addTearDown(container.dispose);
      await hydrateDefault(container, gateway, 956);
      final edit = container.read(editPostControllerProvider(956).notifier);
      final saveFuture = edit.save(categoryId: 2, title: 'N', body: 'N');
      await Future<void>.delayed(const Duration(milliseconds: 30));
      auth.setUser(sampleAuthUser(id: 2));
      await container.read(editPostControllerProvider(956).future);
      final result = await saveFuture;
      expect(result, isA<EditPostSaveDiscarded>());
      final saveAfter = await edit.save(categoryId: 2, title: 'Z', body: 'Z');
      expect(saveAfter, isA<EditPostSaveSuccess>());
    });

    test('10 fallo PATCH 422 libera lock sin incertidumbre', () async {
      final gateway = FakePostGateway(
        detailById: {
          957: draftPostDetail(
            id: 957,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        updateFailureByPostId: {
          957: const ApiValidationFailure({
            'title': ['x'],
          }),
        },
      );
      final container = buildContainer(gateway);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(957).future);
      keepAlive(container, 957);
      final edit = container.read(editPostControllerProvider(957).notifier);
      final result = await edit.save(categoryId: 2, title: 'N', body: 'N');
      expect(result, isA<EditPostSaveFailure>());
      final record = container
          .read(editPostUncertainPatchPersistenceProvider)
          .recordForPost(957);
      expect(record, isNull);
      final attach = container.read(
        editPostAttachmentsControllerProvider(957).notifier,
      );
      final snap = EditPostSnapshot.fromDetail(gateway.detailById![957]!);
      container
          .read(editPostAttachmentsControllerProvider(957).notifier)
          .hydrateFromEditableRevision(
            revisionId: snap.editableRevisionId!,
            serverAttachments: snap.readOnlyAttachments,
          );
      await attach.pickAndAddPdf();
      expect(await attach.uploadPending(), isA<EditPostUploadSuccess>());
    });
  });

  group('4C.2D.1 revisión obsoleta', () {
    test('reload sincroniza revisionId y descarta selección local', () async {
      const oldRev = 9600;
      const newRev = 9601;
      final gateway = FakePostGateway(
        detailById: {960: postDetailWithRevision(id: 960, revisionId: oldRev)},
      );
      final container = buildContainer(gateway);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(960).future);
      keepAlive(container, 960);
      final attach = container.read(
        editPostAttachmentsControllerProvider(960).notifier,
      );
      attach.hydrateFromEditableRevision(
        revisionId: oldRev,
        serverAttachments: const [],
        editorLoadGeneration: 1,
      );
      await attach.pickAndAddPdf();
      expect(
        container.read(editPostAttachmentsControllerProvider(960)).localItems,
        isNotEmpty,
      );
      gateway.detailById![960] = postDetailWithRevision(
        id: 960,
        revisionId: newRev,
      );
      await container.read(editPostControllerProvider(960).notifier).reload();
      final state = container.read(editPostAttachmentsControllerProvider(960));
      expect(state.revisionId, newRev);
      expect(state.localItems, isEmpty);
      expect(state.bannerMessage, contains('revisión editable cambió'));
    });

    test('GET tardío no restaura revisión antigua', () async {
      const oldRev = 9610;
      const newRev = 9611;
      final gateway = FakePostGateway(
        detailById: {961: postDetailWithRevision(id: 961, revisionId: oldRev)},
        detailDelayMs: 50,
      );
      final container = buildContainer(gateway);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(961).future);
      keepAlive(container, 961);
      final attachN = container.read(
        editPostAttachmentsControllerProvider(961).notifier,
      );
      attachN.syncFromEditorSnapshot(
        editorLoadGeneration: 2,
        editable: true,
        editableRevisionId: newRev,
        serverAttachments: const [],
      );
      gateway.detailById![961] = postDetailWithRevision(
        id: 961,
        revisionId: oldRev,
      );
      attachN.syncFromEditorSnapshot(
        editorLoadGeneration: 1,
        editable: true,
        editableRevisionId: oldRev,
        serverAttachments: const [],
      );
      expect(
        container.read(editPostAttachmentsControllerProvider(961)).revisionId,
        newRev,
      );
    });
  });

  group('4C.2D.3 H2 concurrencia PATCH adicional', () {
    test('5 dos save() simultáneos: un PATCH HTTP', () async {
      final gateway = FakePostGateway(
        detailById: {
          990: draftPostDetail(
            id: 990,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        updateDelayMs: 100,
      );
      final container = buildContainer(gateway);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(990).future);
      keepAlive(container, 990);
      final edit = container.read(editPostControllerProvider(990).notifier);
      final results = await Future.wait([
        edit.save(categoryId: 2, title: 'First', body: 'First body'),
        edit.save(categoryId: 2, title: 'Second', body: 'Second body'),
      ]);
      expect(gateway.updatePostCallCount, 1);
      expect(results.whereType<EditPostSaveSuccess>().length, 1);
      expect(
        results.where(
          (r) => r is EditPostSaveBlocked || r is EditPostSaveInFlight,
        ).length,
        1,
      );
    });

    test('6 lease antiguo no libera reserva nueva', () {
      final gateway = FakePostGateway(
        detailById: {
          991: draftPostDetail(
            id: 991,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
      );
      final container = buildContainer(gateway);
      addTearDown(container.dispose);
      final persistence = container.read(
        editPostAttachmentsPersistenceProvider.notifier,
      );
      final auth = container.read(authControllerProvider);
      final userId = (auth as AuthAuthenticated).user.id;
      final epoch =
          container.read(authControllerProvider.notifier).sessionEpoch;
      final leaseA = persistence.tryAcquireExclusive(
        userId: userId,
        sessionEpoch: epoch,
        postId: 991,
        kind: EditPostExclusiveOperationKind.patch,
      );
      expect(leaseA, isNotNull);
      persistence.releaseExclusive(leaseA!);
      final leaseB = persistence.tryAcquireExclusive(
        userId: userId,
        sessionEpoch: epoch,
        postId: 991,
        kind: EditPostExclusiveOperationKind.patch,
      );
      expect(leaseB, isNotNull);
      expect(persistence.releaseExclusive(leaseA), isFalse);
      expect(
        persistence.exclusiveKindForPost(991),
        EditPostExclusiveOperationKind.patch,
      );
      persistence.releaseExclusive(leaseB!);
    });

    test(
      '9 cambio de sesión durante PATCH no bloquea guardado nuevo',
      () async {
        final gateway = FakePostGateway(
          detailById: {
            992: draftPostDetail(
              id: 992,
              groupId: 2,
              categoryId: 2,
              title: 'T',
              body: 'B',
            ),
          },
          updateDelayMs: 100,
        );
        final auth = MutableUserAuthController();
        final container = buildContainer(gateway, authFactory: () => auth);
        addTearDown(container.dispose);
        await container.read(editPostControllerProvider(992).future);
        keepAlive(container, 992);
        final edit = container.read(editPostControllerProvider(992).notifier);
        final slow = edit.save(categoryId: 2, title: 'Old', body: 'Old');
        await Future<void>.delayed(const Duration(milliseconds: 30));
        auth.setUser(sampleAuthUser(id: 3));
        await container.read(editPostControllerProvider(992).future);
        expect(await slow, isA<EditPostSaveDiscarded>());
        final after = await edit.save(categoryId: 2, title: 'New', body: 'New');
        expect(after, isA<EditPostSaveSuccess>());
        expect(gateway.updatePostCallCount, 2);
        final third = await edit.save(categoryId: 2, title: 'Third', body: 'Third');
        expect(third, isA<EditPostSaveSuccess>());
        expect(gateway.updatePostCallCount, 3);
      },
    );
  });

  group('4C.2D.3 H3 upload en vuelo y reload', () {
    test('upload conserva revisionId A; nuevos usan B', () async {
      const revA = 9930;
      const revB = 9931;
      final gateway = FakePostGateway(
        detailById: {993: postDetailWithRevision(id: 993, revisionId: revA)},
        uploadDelayMs: 120,
      );
      final container = buildContainer(gateway);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(993).future);
      keepAlive(container, 993);
      final attach = container.read(
        editPostAttachmentsControllerProvider(993).notifier,
      );
      attach.hydrateFromEditableRevision(
        revisionId: revA,
        serverAttachments: const [],
        editorLoadGeneration: 1,
      );
      await attach.pickAndAddPdf();
      final uploadFuture = attach.uploadPending();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gateway.detailById![993] = postDetailWithRevision(
        id: 993,
        revisionId: revB,
      );
      await container.read(editPostControllerProvider(993).notifier).reload();
      expect(gateway.uploadPayloads.single['revisionId'], revA);
      await uploadFuture;
      expect(
        container.read(editPostAttachmentsControllerProvider(993)).revisionId,
        revB,
      );
      attach.setLocalItemsForTests([
        CreatePostLocalAttachment(
          clientId: 'n2',
          path: pick.path,
          displayName: 'n2.pdf',
          sizeBytes: pick.sizeBytes,
          mimeType: pick.mimeType,
        ),
      ]);
      await attach.uploadPending();
      expect(gateway.uploadPayloads.last['revisionId'], revB);
    });

    test('incierto tras reload conserva revisionId original', () async {
      const revA = 9940;
      const revB = 9941;
      final gateway = FakePostGateway(
        detailById: {994: postDetailWithRevision(id: 994, revisionId: revA)},
        uploadDelayMs: 80,
        uploadThrowsUncertain: true,
      );
      final container = buildContainer(gateway);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(994).future);
      keepAlive(container, 994);
      final attach = container.read(
        editPostAttachmentsControllerProvider(994).notifier,
      );
      attach.hydrateFromEditableRevision(
        revisionId: revA,
        serverAttachments: const [],
        editorLoadGeneration: 1,
      );
      await attach.pickAndAddPdf();
      final uploadFuture = attach.uploadPending();
      gateway.detailById![994] = postDetailWithRevision(
        id: 994,
        revisionId: revB,
      );
      await container.read(editPostControllerProvider(994).notifier).reload();
      await uploadFuture;
      expect(gateway.uploadPayloads.single['revisionId'], revA);
      final record =
          container
              .read(editPostAttachmentsPersistenceProvider)
              .recordForPost(994)!;
      expect(record.revisionId, revB);
      expect(record.uncertainUploads.single.revisionId, revA);
    });
  });

  group('4C.2D.1 picker revalidación', () {
    test('cambio de revisión durante selector descarta archivo', () async {
      const oldRev = 9700;
      const newRev = 9701;
      final gateway = FakePostGateway(
        detailById: {970: postDetailWithRevision(id: 970, revisionId: oldRev)},
      );
      EditPostAttachmentsController? attachRef;
      final container = buildContainer(
        gateway,
        picker: DelayedFakeCreatePostFilePicker(
          pick,
          onBeforeReturn: () {
            attachRef?.syncFromEditorSnapshot(
              editorLoadGeneration: 5,
              editable: true,
              editableRevisionId: newRev,
              serverAttachments: const [],
            );
          },
        ),
      );
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(970).future);
      keepAlive(container, 970);
      final attach = container.read(
        editPostAttachmentsControllerProvider(970).notifier,
      );
      attachRef = attach;
      attach.hydrateFromEditableRevision(
        revisionId: oldRev,
        serverAttachments: const [],
      );
      final message = await attach.pickAndAddPdf();
      expect(message, contains('revisión cambió'));
      expect(
        container.read(editPostAttachmentsControllerProvider(970)).localItems,
        isEmpty,
      );
    });
  });
}
