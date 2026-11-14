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
import 'package:red_vecinal/features/posts/application/create_post_session_persistence.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';
import 'package:red_vecinal/features/posts/support/post_attachment_limits.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

class FakeCreatePostFilePicker implements CreatePostFilePickerPort {
  FakeCreatePostFilePicker(this.file);

  final PickedPostFile? file;

  @override
  Future<PickedPostFile?> pickImage() async => file;

  @override
  Future<PickedPostFile?> pickPdf() async => file;
}

void main() {
  final fixturePdf = File('test/fixtures/tiny_upload.pdf');

  ProviderContainer container(FakePostGateway gateway, {PickedPostFile? pick}) {
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

  test('create con cero adjuntos mantiene flujo 5.4F-2', () async {
    final gateway = FakePostGateway();
    final c = container(gateway);
    addTearDown(c.dispose);

    final result = await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );
    expect(result, isA<CreatePostSendSuccess>());
    expect(gateway.uploadCallCount, 0);
  });

  test('create → upload → submit', () async {
    final gateway = FakePostGateway();
    final c = container(
      gateway,
      pick: PickedPostFile(
        path: fixturePdf.path,
        displayName: 'tiny_upload.pdf',
        sizeBytes: await fixturePdf.length(),
        mimeType: 'application/pdf',
      ),
    );
    addTearDown(c.dispose);

    await c.read(createPostAttachmentsProvider.notifier).pickAndAddPdf();

    final result = await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'Con adjunto',
          body: 'Cuerpo',
        );

    expect(result, isA<CreatePostSendSuccess>());
    expect(gateway.createPostCallCount, 1);
    expect(gateway.uploadCallCount, 1);
    expect(gateway.submitPostCallCount, 1);
  });

  test('bloquea sexto archivo local', () async {
    final pick = PickedPostFile(
      path: fixturePdf.path,
      displayName: 'tiny_upload.pdf',
      sizeBytes: await fixturePdf.length(),
      mimeType: 'application/pdf',
    );
    final c = container(FakePostGateway(), pick: pick);
    addTearDown(c.dispose);
    final notifier = c.read(createPostAttachmentsProvider.notifier);
    for (var i = 0; i < PostAttachmentLimits.maxPerRevision; i++) {
      await notifier.pickAndAddPdf();
    }
    final error = await notifier.pickAndAddPdf();
    expect(error, isNotNull);
    final session = c.read(createPostSessionPersistenceProvider);
    expect(c.read(createPostAttachmentsProvider).remainingSlots(session), 0);
  });

  test('upload incierto bloquea submit', () async {
    final gateway = FakePostGateway(uploadThrowsUncertain: true);
    final c = container(
      gateway,
      pick: PickedPostFile(
        path: fixturePdf.path,
        displayName: 'tiny_upload.pdf',
        sizeBytes: await fixturePdf.length(),
        mimeType: 'application/pdf',
      ),
    );
    addTearDown(c.dispose);
    await c.read(createPostAttachmentsProvider.notifier).pickAndAddPdf();
    final result = await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );
    expect(result, isA<CreatePostSendUploadUncertain>());
    expect(gateway.submitPostCallCount, 0);
    expect(
      c.read(createPostSessionPersistenceProvider).hasUnresolvedUncertainUpload,
      isTrue,
    );
  });
}
