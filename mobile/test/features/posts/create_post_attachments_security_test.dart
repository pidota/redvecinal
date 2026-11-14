import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/application/create_post_attachments_controller.dart';
import 'package:red_vecinal/features/posts/application/create_post_controller.dart';
import 'package:red_vecinal/features/posts/application/create_post_file_picker.dart';
import 'package:red_vecinal/features/posts/application/create_post_local_attachment.dart';
import 'package:red_vecinal/features/posts/application/create_post_session_persistence.dart';
import 'package:red_vecinal/features/posts/application/create_post_uncertain_upload_record.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';
import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'create_post_attachments_flow_test.dart';
import 'post_test_support.dart';

PostDetail draftWithAttachmentCount({required int id, required int count}) {
  final json = Map<String, dynamic>.from(sampleCommunityPostJson(id: id));
  json['status'] = 'draft';
  json['content'] = null;
  json['attachments'] = [
    for (var i = 0; i < count; i++)
      {
        'id': 5000 + i,
        'revision_id': id * 10,
        'original_display_name': 'f$i.pdf',
        'mime_type': 'application/pdf',
        'size_bytes': 10,
        'download_url': '/api/v1/posts/$id/attachments/${5000 + i}',
      },
  ];
  json['working_content'] = {'revision_id': id * 10, 'title': 'T', 'body': 'B'};
  return PostDetail.fromJson(json);
}

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

  test('A: upload incierto → remount → GET vacío → submit bloqueado', () async {
    final gateway = FakePostGateway(uploadThrowsUncertain: true);
    final c = container(gateway);
    addTearDown(c.dispose);
    c.read(createPostAttachmentsProvider);
    await c.read(createPostAttachmentsProvider.notifier).pickAndAddPdf();
    await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );
    final draftId =
        c.read(createPostSessionPersistenceProvider).confirmedDraftId;
    expect(draftId, isNotNull);
    c.invalidate(createPostAttachmentsProvider);
    final remounted = c.read(createPostAttachmentsProvider);
    expect(
      remounted.hasBlockingUncertain(
        c.read(createPostSessionPersistenceProvider),
      ),
      isTrue,
    );

    final reconcile =
        await c
            .read(createPostControllerProvider.notifier)
            .reconcileUploadsFromServer();
    expect(reconcile, isA<CreatePostSendReconcileInconclusive>());
    expect(
      c.read(createPostSessionPersistenceProvider).hasUnresolvedUncertainUpload,
      isTrue,
    );

    final retry = await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );
    expect(retry, isA<CreatePostSendUploadUncertain>());
    expect(gateway.submitPostCallCount, 0);
  });

  test('B: upload incierto → ID ajeno → sigue uncertain', () async {
    final gateway = FakePostGateway(uploadThrowsUncertain: true);
    final c = container(gateway);
    addTearDown(c.dispose);
    c.read(createPostAttachmentsProvider);
    await c.read(createPostAttachmentsProvider.notifier).pickAndAddPdf();
    await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );
    final draftId =
        c.read(createPostSessionPersistenceProvider).confirmedDraftId!;
    gateway.detailById = {
      draftId: draftWithAttachmentCount(id: draftId, count: 1),
    };
    await c
        .read(createPostControllerProvider.notifier)
        .reconcileUploadsFromServer();
    final item = c.read(createPostAttachmentsProvider).items.single;
    expect(item.state, CreatePostAttachmentState.uncertain);
    expect(
      c.read(createPostSessionPersistenceProvider).hasUnresolvedUncertainUpload,
      isTrue,
    );
  });

  test('C: GET de reconciliación falla → bloqueo conservado', () async {
    final gateway = FakePostGateway(uploadThrowsUncertain: true);
    final c = container(gateway);
    addTearDown(c.dispose);
    c.read(createPostAttachmentsProvider);
    await c.read(createPostAttachmentsProvider.notifier).pickAndAddPdf();
    await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );
    final draftId =
        c.read(createPostSessionPersistenceProvider).confirmedDraftId!;
    gateway.detailFailureById = {draftId: const ApiNetworkFailure()};
    final reconcile =
        await c
            .read(createPostControllerProvider.notifier)
            .reconcileUploadsFromServer();
    expect(reconcile, isA<CreatePostSendCreateFailed>());
    expect(
      c.read(createPostSessionPersistenceProvider).hasUnresolvedUncertainUpload,
      isTrue,
    );
  });

  test('D: dos inciertos no reciben IDs FIFO', () {
    final c = container(FakePostGateway());
    addTearDown(c.dispose);
    c.read(createPostAttachmentsProvider);
    final notifier = c.read(createPostAttachmentsProvider.notifier);
    final persistence = c.read(createPostSessionPersistenceProvider.notifier);
    persistence.registerUncertainUpload(
      const CreatePostUncertainUploadRecord(
        clientId: 'c1',
        displayName: 'a.pdf',
        sizeBytes: 1,
        mimeType: 'application/pdf',
      ),
    );
    persistence.registerUncertainUpload(
      const CreatePostUncertainUploadRecord(
        clientId: 'c2',
        displayName: 'b.pdf',
        sizeBytes: 1,
        mimeType: 'application/pdf',
      ),
    );
    notifier.setLocalItemsForTests([
      CreatePostLocalAttachment(
        clientId: 'c1',
        path: '',
        displayName: 'a.pdf',
        sizeBytes: 1,
        mimeType: 'application/pdf',
        state: CreatePostAttachmentState.uncertain,
      ),
      CreatePostLocalAttachment(
        clientId: 'c2',
        path: '',
        displayName: 'b.pdf',
        sizeBytes: 1,
        mimeType: 'application/pdf',
        state: CreatePostAttachmentState.uncertain,
      ),
    ]);
    notifier.applyServerAttachmentSnapshot(
      serverAttachmentIds: const [9001, 9002],
      unresolvedUncertain: true,
    );
    final states =
        c.read(createPostAttachmentsProvider).items.map((e) => e.state).toSet();
    expect(states, {CreatePostAttachmentState.uncertain});
  });

  test('E: logout limpia incertidumbre de sesión', () async {
    final gateway = FakePostGateway(uploadThrowsUncertain: true);
    final c = container(gateway);
    addTearDown(c.dispose);
    c.read(createPostAttachmentsProvider);
    await c.read(createPostAttachmentsProvider.notifier).pickAndAddPdf();
    await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );
    expect(
      c.read(createPostSessionPersistenceProvider).hasUnresolvedUncertainUpload,
      isTrue,
    );
    await c.read(authControllerProvider.notifier).logout();
    c.listen(createPostSessionPersistenceProvider, (_, _) {});
    expect(
      c.read(createPostSessionPersistenceProvider).hasUnresolvedUncertainUpload,
      isFalse,
    );
  });

  test('I: doble tap con confirmedDraftId — un solo flujo', () async {
    final gateway = FakePostGateway(submitPostDelayMs: 100);
    final c = container(gateway);
    addTearDown(c.dispose);
    final draft = draftPostDetail(
      id: 905,
      groupId: 2,
      categoryId: 2,
      title: 'T',
      body: 'B',
    );
    gateway.detailById = {905: draft};
    c
        .read(createPostSessionPersistenceProvider.notifier)
        .setConfirmedDraftId(905, clearUncertain: true);
    final first =
        c.read(createPostControllerProvider.notifier).retrySubmitOnly();
    final second =
        c.read(createPostControllerProvider.notifier).retrySubmitOnly();
    final results = await Future.wait([first, second]);
    expect(results.any((r) => r is CreatePostSendInFlight), isTrue);
    expect(gateway.createPostCallCount, 0);
  });

  test('G: borrador con 5 adjuntos bloquea sexto', () async {
    final gateway = FakePostGateway();
    final c = container(gateway);
    addTearDown(c.dispose);
    const draftId = 901;
    gateway.detailById = {
      draftId: draftWithAttachmentCount(id: draftId, count: 5),
    };
    c
        .read(createPostSessionPersistenceProvider.notifier)
        .setConfirmedDraftId(draftId, clearUncertain: true);
    await c
        .read(createPostControllerProvider.notifier)
        .hydrateConfirmedDraftIfNeeded();
    final err = c.read(createPostAttachmentsProvider);
    await c.read(createPostAttachmentsProvider.notifier).pickAndAddPdf();
    expect(err, isNotNull);
  });

  test('J: reingreso borrador pending sin upload', () async {
    final gateway = FakePostGateway();
    final c = container(gateway);
    addTearDown(c.dispose);
    const draftId = 902;
    gateway.detailById = {draftId: pendingPostDetail(id: draftId)};
    c
        .read(createPostSessionPersistenceProvider.notifier)
        .setConfirmedDraftId(draftId, clearUncertain: true);
    await c
        .read(createPostControllerProvider.notifier)
        .hydrateConfirmedDraftIfNeeded();
    expect(
      c.read(createPostSessionPersistenceProvider).linkedDraftPending,
      isTrue,
    );
    final result = await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );
    expect(result, isA<CreatePostSendAttachmentsBlocked>());
    expect(gateway.uploadCallCount, 0);
  });

  test('K: HTTP 201 confirma y libera incertidumbre', () async {
    final gateway = FakePostGateway(uploadThrowsUncertain: true);
    final c = container(gateway);
    addTearDown(c.dispose);
    c.read(createPostAttachmentsProvider);
    await c.read(createPostAttachmentsProvider.notifier).pickAndAddPdf();
    await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );
    final item = c.read(createPostAttachmentsProvider).items.single;
    final persistence = c.read(createPostSessionPersistenceProvider.notifier);
    expect(
      c.read(createPostSessionPersistenceProvider).hasUnresolvedUncertainUpload,
      isTrue,
    );

    persistence.recordUploadedAttachment(7001);
    persistence.resolveUncertainUpload(item.clientId);
    c
        .read(createPostAttachmentsProvider.notifier)
        .applyItemUpdate(
          item.copyWith(
            state: CreatePostAttachmentState.uploaded,
            serverAttachmentId: 7001,
            clearUserMessage: true,
          ),
        );

    expect(
      c.read(createPostSessionPersistenceProvider).hasUnresolvedUncertainUpload,
      isFalse,
    );
    expect(
      c.read(createPostAttachmentsProvider).items.single.state,
      CreatePostAttachmentState.uploaded,
    );
  });

  test('L: submit fallido no recrea post', () async {
    final gateway = FakePostGateway();
    gateway.submitFailureByPostId = {901: const ApiServerFailure()};
    final c = container(gateway);
    addTearDown(c.dispose);
    c.read(createPostAttachmentsProvider);
    await c.read(createPostAttachmentsProvider.notifier).pickAndAddPdf();
    final first = await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );
    expect(first, isA<CreatePostSendDraftOnly>());
    final draftId =
        c.read(createPostSessionPersistenceProvider).confirmedDraftId!;
    gateway.submitFailureByPostId = {draftId: const ApiServerFailure()};
    await c.read(createPostControllerProvider.notifier).retrySubmitOnly();
    expect(gateway.createPostCallCount, 1);
    expect(
      c.read(createPostSessionPersistenceProvider).confirmedDraftId,
      draftId,
    );
  });

  test('M: reconciliación concurrente — segunda en vuelo', () async {
    final gateway = FakePostGateway(detailDelayMs: 60);
    final c = container(gateway);
    addTearDown(c.dispose);
    c
        .read(createPostSessionPersistenceProvider.notifier)
        .setConfirmedDraftId(903, clearUncertain: true);
    gateway.detailById = {
      903: draftPostDetail(
        id: 903,
        groupId: 2,
        categoryId: 2,
        title: 'T',
        body: 'B',
      ),
    };
    c
        .read(createPostSessionPersistenceProvider.notifier)
        .registerUncertainUpload(
          const CreatePostUncertainUploadRecord(
            clientId: 'z',
            displayName: 'z.pdf',
            sizeBytes: 1,
            mimeType: 'application/pdf',
          ),
        );
    final first =
        c
            .read(createPostControllerProvider.notifier)
            .reconcileUploadsFromServer();
    final second =
        c
            .read(createPostControllerProvider.notifier)
            .reconcileUploadsFromServer();
    final results = await Future.wait([first, second]);
    expect(results.any((r) => r is CreatePostSendInFlight), isTrue);
    expect(
      c.read(createPostSessionPersistenceProvider).hasUnresolvedUncertainUpload,
      isTrue,
    );
  });

  test('N: remount provider mantiene bloqueo', () async {
    final gateway = FakePostGateway(uploadThrowsUncertain: true);
    final c = container(gateway);
    addTearDown(c.dispose);
    c.read(createPostAttachmentsProvider);
    await c.read(createPostAttachmentsProvider.notifier).pickAndAddPdf();
    await c
        .read(createPostControllerProvider.notifier)
        .sendForReview(
          neighborhoodGroupId: 2,
          categoryId: 2,
          title: 'T',
          body: 'B',
        );
    c.invalidate(createPostAttachmentsProvider);
    final session = c.read(createPostSessionPersistenceProvider);
    expect(session.hasUnresolvedUncertainUpload, isTrue);
    final state = c.read(createPostAttachmentsProvider);
    expect(state.hasBlockingUncertain(session), isTrue);
    expect(state.items, isNotEmpty);
  });
}
