import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/application/create_post_file_picker.dart';
import 'package:red_vecinal/features/posts/application/edit_post_attachments_controller.dart';
import 'package:red_vecinal/features/posts/application/edit_post_attachments_persistence.dart';
import 'package:red_vecinal/features/posts/application/edit_post_controller.dart';
import 'package:red_vecinal/features/posts/application/edit_post_uncertain_patch_persistence.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'create_post_attachments_flow_test.dart';
import 'post_test_support.dart';

PostDetail postDetailAtRevision({
  required int id,
  required int revisionId,
  List<Map<String, dynamic>>? attachments,
}) {
  return draftPostDetail(
    id: id,
    groupId: 2,
    categoryId: 2,
    title: 'T',
    body: 'B',
    revisionId: revisionId,
    attachments: attachments,
  );
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

  ProviderContainer container(
    FakePostGateway gateway, {
    AuthController Function()? authFactory,
  }) {
    final c = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        postRepositoryProvider.overrideWithValue(gateway),
        createPostFilePickerProvider.overrideWithValue(
          FakeCreatePostFilePicker(pick),
        ),
        authControllerProvider.overrideWith(
          authFactory ?? AuthenticatedBootAuthController.new,
        ),
      ],
    );
    c.read(editPostAttachmentsPersistenceProvider);
    c.read(editPostUncertainPatchPersistenceProvider);
    return c;
  }

  void keepAlive(ProviderContainer c, int postId) {
    c.listen(editPostControllerProvider(postId), (_, __) {});
    c.listen(editPostAttachmentsControllerProvider(postId), (_, __) {});
  }

  group('4C.2D.3 H1 sync tras PATCH', () {
    test('1 PATCH exitoso conserva revisionId en adjuntos', () async {
      const rev = 9801;
      final gateway = FakePostGateway(
        detailById: {980: postDetailAtRevision(id: 980, revisionId: rev)},
      );
      final c = container(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(980).future);
      keepAlive(c, 980);
      c
          .read(editPostAttachmentsControllerProvider(980).notifier)
          .hydrateFromEditableRevision(
            revisionId: rev,
            serverAttachments: const [],
            editorLoadGeneration: 1,
          );
      final result = await c
          .read(editPostControllerProvider(980).notifier)
          .save(categoryId: 2, title: 'N', body: 'N');
      expect(result, isA<EditPostSaveSuccess>());
      expect(
        c.read(editPostAttachmentsControllerProvider(980)).revisionId,
        rev,
      );
      expect(gateway.updatePostCallCount, 1);
    });

    test('2 PATCH con revisionId distinto sincroniza adjuntos', () async {
      const oldRev = 9810;
      const newRev = 9811;
      final gateway = FakePostGateway(
        detailById: {
          981: postDetailAtRevision(
            id: 981,
            revisionId: oldRev,
            attachments: [
              {
                'id': 50,
                'revision_id': oldRev,
                'original_display_name': 'viejo.pdf',
                'mime_type': 'application/pdf',
                'size_bytes': 10,
                'download_url': '/api/v1/posts/981/attachments/50',
              },
            ],
          ),
        },
        updatedDetailByPostId: {
          981: postDetailAtRevision(
            id: 981,
            revisionId: newRev,
            attachments: [
              {
                'id': 51,
                'revision_id': newRev,
                'original_display_name': 'nuevo.pdf',
                'mime_type': 'application/pdf',
                'size_bytes': 10,
                'download_url': '/api/v1/posts/981/attachments/51',
              },
            ],
          ),
        },
      );
      final c = container(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(981).future);
      keepAlive(c, 981);
      c
          .read(editPostAttachmentsControllerProvider(981).notifier)
          .hydrateFromEditableRevision(
            revisionId: oldRev,
            serverAttachments:
                EditPostSnapshot.fromDetail(
                  gateway.detailById![981]!,
                ).readOnlyAttachments,
            editorLoadGeneration: 1,
          );
      await c
          .read(editPostControllerProvider(981).notifier)
          .save(categoryId: 2, title: 'N', body: 'N');
      final attach = c.read(editPostAttachmentsControllerProvider(981));
      expect(attach.revisionId, newRev);
      expect(attach.serverAttachmentIds, [51]);
    });

    test('3 PATCH tardío no restaura revisión tras reload', () async {
      const oldRev = 9820;
      const newRev = 9821;
      final gateway = FakePostGateway(
        detailById: {982: postDetailAtRevision(id: 982, revisionId: oldRev)},
        updateDelayMs: 120,
        updatedDetailByPostId: {
          982: postDetailAtRevision(id: 982, revisionId: oldRev),
        },
      );
      final c = container(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(982).future);
      keepAlive(c, 982);
      c
          .read(editPostAttachmentsControllerProvider(982).notifier)
          .hydrateFromEditableRevision(
            revisionId: oldRev,
            serverAttachments: const [],
            editorLoadGeneration: 1,
          );
      final edit = c.read(editPostControllerProvider(982).notifier);
      final saveFuture = edit.save(categoryId: 2, title: 'Stale', body: 'Stale');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      edit.debugAdvanceEditorContentGeneration();
      c
          .read(editPostAttachmentsControllerProvider(982).notifier)
          .syncFromEditorSnapshot(
            editorLoadGeneration: 10,
            editable: true,
            editableRevisionId: newRev,
            serverAttachments: const [],
          );
      final saveResult = await saveFuture;
      expect(saveResult, isA<EditPostSaveDiscarded>());
      expect(
        c.read(editPostAttachmentsControllerProvider(982)).revisionId,
        newRev,
      );
    });

    test('4 PATCH exitoso no borra upload incierto', () async {
      const rev = 9830;
      final gateway = FakePostGateway(
        detailById: {983: postDetailAtRevision(id: 983, revisionId: rev)},
        uploadThrowsUncertain: true,
      );
      final c = container(gateway);
      addTearDown(c.dispose);
      await c.read(editPostControllerProvider(983).future);
      keepAlive(c, 983);
      final attachN = c.read(
        editPostAttachmentsControllerProvider(983).notifier,
      );
      attachN.hydrateFromEditableRevision(
        revisionId: rev,
        serverAttachments: const [],
        editorLoadGeneration: 1,
      );
      await attachN.pickAndAddPdf();
      await attachN.uploadPending();
      expect(
        c
            .read(editPostAttachmentsPersistenceProvider)
            .recordForPost(983)!
            .hasUnresolvedUncertain,
        isTrue,
      );
      await c
          .read(editPostControllerProvider(983).notifier)
          .save(categoryId: 2, title: 'N', body: 'N');
      expect(
        c.read(editPostAttachmentsControllerProvider(983)).hasBlockingUncertain,
        isTrue,
      );
      final record =
          c.read(editPostAttachmentsPersistenceProvider).recordForPost(983)!;
      expect(record.revisionId, rev);
      expect(record.uncertainUploads.single.revisionId, rev);
    });

    test('5 PATCH en otra sesión no altera adjuntos ajenos', () async {
      const rev = 9840;
      final cA = container(
        FakePostGateway(
          detailById: {984: postDetailAtRevision(id: 984, revisionId: rev)},
        ),
      );
      addTearDown(cA.dispose);
      await cA.read(editPostControllerProvider(984).future);
      keepAlive(cA, 984);
      cA
          .read(editPostAttachmentsControllerProvider(984).notifier)
          .hydrateFromEditableRevision(
            revisionId: rev,
            serverAttachments: const [],
            editorLoadGeneration: 1,
          );

      final cB = ProviderContainer(
        overrides: [
          appConfigProvider.overrideWithValue(testAppConfig),
          authRepositoryProvider.overrideWithValue(
            FakeAuthGateway(meUser: sampleAuthUser(id: 99)),
          ),
          tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
          postRepositoryProvider.overrideWithValue(
            FakePostGateway(
              detailById: {984: postDetailAtRevision(id: 984, revisionId: rev)},
            ),
          ),
          createPostFilePickerProvider.overrideWithValue(
            FakeCreatePostFilePicker(pick),
          ),
          authControllerProvider.overrideWith(
            AuthenticatedBootAuthController.new,
          ),
        ],
      );
      addTearDown(cB.dispose);
      cB.read(editPostAttachmentsPersistenceProvider);
      await cB.read(editPostControllerProvider(984).future);
      await cB
          .read(editPostControllerProvider(984).notifier)
          .save(categoryId: 2, title: 'Otro', body: 'Otro');

      final attachA = cA.read(editPostAttachmentsControllerProvider(984));
      expect(attachA.revisionId, rev);
      expect(
        cA.read(editPostAttachmentsPersistenceProvider).recordForPost(984)!.userId,
        1,
      );
    });
  });
}
