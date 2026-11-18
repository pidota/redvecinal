import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/application/create_post_file_picker.dart';
import 'package:red_vecinal/features/posts/application/create_post_local_attachment.dart';
import 'package:red_vecinal/features/posts/application/edit_post_attachments_controller.dart';
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

  ProviderContainer container(FakePostGateway gateway) {
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
          AuthenticatedBootAuthController.new,
        ),
      ],
    );
    c.read(editPostAttachmentsPersistenceProvider);
    c.read(editPostUncertainSubmitPersistenceProvider);
    return c;
  }

  Future<void> runDraftFlow() async {
    final g = FakePostGateway(
      detailById: {
        1601: draftPostDetail(
          id: 1601,
          groupId: 2,
          categoryId: 2,
          title: 'Inicial',
          body: 'Cuerpo inicial',
        ),
      },
      myPostsPage: const PaginatedFeedPosts(
        items: [],
        currentPage: 1,
        lastPage: 1,
      ),
    );
    final c = container(g);
    addTearDown(c.dispose);
    c.listen(editPostControllerProvider(1601), (_, __) {});
    c.listen(editPostAttachmentsControllerProvider(1601), (_, __) {});
    await c.read(editPostControllerProvider(1601).future);
    final detailCallsAfterLoad = g.detailCallCount;
    final attach = c.read(editPostAttachmentsControllerProvider(1601).notifier);
    attach.hydrateFromEditableRevision(
      revisionId: g.detailById![1601]!.editableRevisionId!,
      serverAttachments: [],
      editorLoadGeneration: 1,
    );

    final edit = c.read(editPostControllerProvider(1601).notifier);
    final save = await edit.save(
      categoryId: 2,
      title: 'Editado',
      body: 'Cuerpo editado',
    );
    expect(save, isA<EditPostSaveSuccess>());
    expect(g.updatePostCallCount, 1);

    attach.setLocalItemsForTests([
      CreatePostLocalAttachment(
        clientId: 'flow1',
        path: pick.path,
        displayName: 'flow1.pdf',
        sizeBytes: pick.sizeBytes,
        mimeType: pick.mimeType,
      ),
    ]);
    expect(await attach.uploadPending(), isA<EditPostUploadSuccess>());
    expect(g.uploadCallCount, 1);

    final submit = await edit.submitToModeration(
      categoryId: 2,
      title: 'Editado',
      body: 'Cuerpo editado',
    );
    expect(submit, isA<EditPostSubmitSuccess>());
    expect(g.submitPostCallCount, 1);
    expect(
      c
          .read(editPostControllerProvider(1601))
          .requireValue
          .snapshot
          .detail
          .status,
      'pending',
    );
    expect(c.read(editPostControllerProvider(1601).notifier), isNotNull);
    expect(g.detailCallCount, greaterThanOrEqualTo(detailCallsAfterLoad));
    expect(
      g.updatePostCallCount + g.uploadCallCount + g.submitPostCallCount,
      3,
    );
  }

  Future<void> runRejectedFlow() async {
    final g = FakePostGateway(
      detailById: {
        1602: rejectedPostDetail(
          id: 1602,
          groupId: 2,
          categoryId: 2,
          title: 'Rechazado',
          body: 'Motivo',
        ),
      },
      myPostsPage: const PaginatedFeedPosts(
        items: [],
        currentPage: 1,
        lastPage: 1,
      ),
    );
    final c = container(g);
    addTearDown(c.dispose);
    c.listen(editPostControllerProvider(1602), (_, __) {});
    await c.read(editPostControllerProvider(1602).future);
    c
        .read(editPostAttachmentsControllerProvider(1602).notifier)
        .hydrateFromEditableRevision(
          revisionId: g.detailById![1602]!.editableRevisionId!,
          serverAttachments: [],
          editorLoadGeneration: 1,
        );

    final edit = c.read(editPostControllerProvider(1602).notifier);
    expect(
      await edit.save(
        categoryId: 2,
        title: 'Corregido',
        body: 'Texto corregido',
      ),
      isA<EditPostSaveSuccess>(),
    );
    expect(
      await edit.submitToModeration(
        categoryId: 2,
        title: 'Corregido',
        body: 'Texto corregido',
      ),
      isA<EditPostSubmitSuccess>(),
    );
    expect(g.submitPostCallCount, 1);
    expect(
      g.updatePostCallCount + g.uploadCallCount + g.submitPostCallCount,
      greaterThanOrEqualTo(1),
    );
  }

  group('4C.2G flujo integrado edición', () {
    test('draft: PATCH → upload → submit → Mis publicaciones', runDraftFlow);
    test('rejected: guardar → reenviar → pending', runRejectedFlow);
  });
}
