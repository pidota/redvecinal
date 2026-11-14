import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/application/create_post_attachments_controller.dart';
import 'package:red_vecinal/features/posts/application/create_post_controller.dart';
import 'package:red_vecinal/features/posts/application/create_post_file_picker.dart';
import 'package:red_vecinal/features/posts/application/create_post_local_attachment.dart';
import 'package:red_vecinal/features/posts/application/create_post_session_persistence.dart';
import 'package:red_vecinal/features/posts/application/create_post_uncertain_upload_record.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'create_post_attachments_flow_test.dart';
import 'post_test_support.dart';

void main() {
  final fixturePdf = File('test/fixtures/tiny_upload.pdf');
  late PickedPostFile pick;

  setUpAll(() async {
    pick = PickedPostFile(
      path: fixturePdf.path,
      displayName: 'tiny_upload.pdf',
      sizeBytes: await fixturePdf.length(),
      mimeType: 'application/pdf',
    );
  });

  ProviderContainer container(FakePostGateway gateway) {
    return ProviderContainer(
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
  }

  test('A: markRetryAllowed rechaza uncertain', () {
    final c = container(FakePostGateway());
    addTearDown(c.dispose);
    c.read(createPostAttachmentsProvider);
    final notifier = c.read(createPostAttachmentsProvider.notifier);
    notifier.setLocalItemsForTests([
      CreatePostLocalAttachment(
        clientId: 'u1',
        path: fixturePdf.path,
        displayName: 'a.pdf',
        sizeBytes: 1,
        mimeType: 'application/pdf',
        state: CreatePostAttachmentState.uncertain,
      ),
    ]);
    c.read(createPostSessionPersistenceProvider.notifier).registerUncertainUpload(
      const CreatePostUncertainUploadRecord(
        clientId: 'u1',
        displayName: 'a.pdf',
        sizeBytes: 1,
        mimeType: 'application/pdf',
      ),
    );
    c.read(createPostAttachmentsProvider);
    final retryNotifier = c.read(createPostAttachmentsProvider.notifier);
    expect(retryNotifier.markRetryAllowed('u1'), isFalse);
    expect(
      c.read(createPostAttachmentsProvider).items.single.state,
      CreatePostAttachmentState.uncertain,
    );
  });

  test('B: markRetryAllowed permite failed inequívoco', () {
    final c = container(FakePostGateway());
    addTearDown(c.dispose);
    c.read(createPostAttachmentsProvider);
    final notifier = c.read(createPostAttachmentsProvider.notifier);
    notifier.setLocalItemsForTests([
      CreatePostLocalAttachment(
        clientId: 'f1',
        path: fixturePdf.path,
        displayName: 'a.pdf',
        sizeBytes: 1,
        mimeType: 'application/pdf',
        state: CreatePostAttachmentState.failed,
      ),
    ]);
    expect(notifier.markRetryAllowed('f1'), isTrue);
    expect(
      c.read(createPostAttachmentsProvider).items.single.state,
      CreatePostAttachmentState.selected,
    );
  });

  test('C: retrySubmitOnly no sube clientId incierto', () async {
    final gateway = FakePostGateway();
    final c = container(gateway);
    addTearDown(c.dispose);
    const draftId = 901;
    gateway.detailById = {
      draftId: draftPostDetail(
        id: draftId,
        groupId: 2,
        categoryId: 2,
        title: 'T',
        body: 'B',
      ),
    };
    c
        .read(createPostSessionPersistenceProvider.notifier)
        .setConfirmedDraftId(draftId, clearUncertain: true);
    c
        .read(createPostSessionPersistenceProvider.notifier)
        .registerUncertainUpload(
          const CreatePostUncertainUploadRecord(
            clientId: 'u1',
            displayName: 'x.pdf',
            sizeBytes: 1,
            mimeType: 'application/pdf',
            localPath: 'x',
          ),
        );
    c.read(createPostAttachmentsProvider.notifier).setLocalItemsForTests([
      CreatePostLocalAttachment(
        clientId: 'u1',
        path: fixturePdf.path,
        displayName: 'x.pdf',
        sizeBytes: 1,
        mimeType: 'application/pdf',
        state: CreatePostAttachmentState.selected,
      ),
    ]);
    final result =
        await c.read(createPostControllerProvider.notifier).retrySubmitOnly();
    expect(result, isA<CreatePostSendUploadUncertain>());
    expect(gateway.uploadCallCount, 0);
  });

  test('J: no submit con incertidumbre pendiente', () async {
    final gateway = FakePostGateway();
    final c = container(gateway);
    addTearDown(c.dispose);
    c
        .read(createPostSessionPersistenceProvider.notifier)
        .setConfirmedDraftId(902, clearUncertain: true);
    c
        .read(createPostSessionPersistenceProvider.notifier)
        .registerUncertainUpload(
          const CreatePostUncertainUploadRecord(
            clientId: 'u1',
            displayName: 'x.pdf',
            sizeBytes: 1,
            mimeType: 'application/pdf',
          ),
        );
    final result =
        await c.read(createPostControllerProvider.notifier).retrySubmitOnly();
    expect(result, isA<CreatePostSendUploadUncertain>());
    expect(gateway.submitPostCallCount, 0);
  });

  test('K: failed no se confunde con uncertain en markRetry', () {
    final c = container(FakePostGateway());
    addTearDown(c.dispose);
    c.read(createPostAttachmentsProvider);
    final notifier = c.read(createPostAttachmentsProvider.notifier);
    notifier.setLocalItemsForTests([
      CreatePostLocalAttachment(
        clientId: 'f1',
        path: fixturePdf.path,
        displayName: 'ok.pdf',
        sizeBytes: 1,
        mimeType: 'application/pdf',
        state: CreatePostAttachmentState.failed,
      ),
      CreatePostLocalAttachment(
        clientId: 'u1',
        path: '',
        displayName: 'bad.pdf',
        sizeBytes: 1,
        mimeType: 'application/pdf',
        state: CreatePostAttachmentState.uncertain,
      ),
    ]);
    c
        .read(createPostSessionPersistenceProvider.notifier)
        .registerUncertainUpload(
          const CreatePostUncertainUploadRecord(
            clientId: 'u1',
            displayName: 'bad.pdf',
            sizeBytes: 1,
            mimeType: 'application/pdf',
          ),
        );
    c.read(createPostAttachmentsProvider);
    final retryNotifier = c.read(createPostAttachmentsProvider.notifier);
    expect(retryNotifier.markRetryAllowed('u1'), isFalse);
    expect(retryNotifier.markRetryAllowed('f1'), isTrue);
  });

  test('G: doble retrySubmitOnly no duplica upload', () async {
    final gateway = FakePostGateway(submitPostDelayMs: 80);
    final c = container(gateway);
    addTearDown(c.dispose);
    const draftId = 903;
    gateway.detailById = {
      draftId: draftPostDetail(
        id: draftId,
        groupId: 2,
        categoryId: 2,
        title: 'T',
        body: 'B',
      ),
    };
    c
        .read(createPostSessionPersistenceProvider.notifier)
        .setConfirmedDraftId(draftId, clearUncertain: true);
    final first =
        c.read(createPostControllerProvider.notifier).retrySubmitOnly();
    final second =
        c.read(createPostControllerProvider.notifier).retrySubmitOnly();
    await Future.wait([first, second]);
    expect(gateway.uploadCallCount, lessThanOrEqualTo(1));
  });
}
