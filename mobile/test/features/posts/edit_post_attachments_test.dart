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
import 'package:red_vecinal/features/posts/application/edit_post_attachments_persistence.dart';
import 'package:red_vecinal/features/posts/application/edit_post_controller.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';
import 'package:red_vecinal/features/posts/support/post_attachment_limits.dart';
import 'package:red_vecinal/features/posts/support/post_attachment_picker_validation.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'create_post_attachments_flow_test.dart';
import 'post_test_support.dart';

PostDetail draftWithMixedAttachments(int id) {
  return PostDetail.fromJson({
    ...Map<String, dynamic>.from(sampleCommunityPostJson(id: id)),
    'status': 'draft',
    'content': null,
    'working_content': {'revision_id': id * 10, 'title': 'T', 'body': 'B'},
    'attachments': [
      {
        'id': 1,
        'revision_id': id * 10,
        'original_display_name': 'ok.pdf',
        'mime_type': 'application/pdf',
        'size_bytes': 10,
        'download_url': '/api/v1/posts/$id/attachments/1',
      },
      {
        'id': 2,
        'revision_id': id * 10 + 99,
        'original_display_name': 'otra.pdf',
        'mime_type': 'application/pdf',
        'size_bytes': 10,
        'download_url': '/api/v1/posts/$id/attachments/2',
      },
    ],
  });
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

  ProviderContainer c(FakePostGateway gateway, {PickedPostFile? picker}) {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        postRepositoryProvider.overrideWithValue(gateway),
        createPostFilePickerProvider.overrideWithValue(
          FakeCreatePostFilePicker(picker ?? pick),
        ),
        authControllerProvider.overrideWith(
          AuthenticatedBootAuthController.new,
        ),
      ],
    );
    container.read(editPostAttachmentsPersistenceProvider);
    return container;
  }

  group('4C.2C adjuntos en edición', () {
    test('1 hidratación de adjuntos existentes', () async {
      final detail = draftWithMixedAttachments(801);
      final gateway = FakePostGateway(detailById: {801: detail});
      final container = c(gateway);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(801).future);
      keepAlive(container, 801);
      final snap = EditPostSnapshot.fromDetail(detail);
      container
          .read(editPostAttachmentsControllerProvider(801).notifier)
          .hydrateFromEditableRevision(
            revisionId: snap.editableRevisionId!,
            serverAttachments: snap.readOnlyAttachments,
          );
      final state = container.read(editPostAttachmentsControllerProvider(801));
      expect(state.serverAttachments.length, 1);
      expect(state.serverAttachments.first.id, 1);
    });

    test('2 filtrado por revisionId', () {
      final snap = EditPostSnapshot.fromDetail(draftWithMixedAttachments(802));
      expect(snap.readOnlyAttachments.length, 1);
      expect(snap.readOnlyAttachments.first.revisionId, 8020);
    });

    test('3 sin mezcla entre publicaciones', () async {
      final g = FakePostGateway(
        detailById: {
          803: draftPostDetail(
            id: 803,
            groupId: 2,
            categoryId: 2,
            title: 'A',
            body: 'A',
          ),
          804: draftPostDetail(
            id: 804,
            groupId: 2,
            categoryId: 2,
            title: 'B',
            body: 'B',
          ),
        },
      );
      final container = c(g);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(803).future);
      keepAlive(container, 803);
      await container.read(editPostControllerProvider(804).future);
      keepAlive(container, 804);
      final s803 = EditPostSnapshot.fromDetail(g.detailById![803]!);
      container
          .read(editPostAttachmentsControllerProvider(803).notifier)
          .hydrateFromEditableRevision(
            revisionId: s803.editableRevisionId!,
            serverAttachments: s803.readOnlyAttachments,
          );
      expect(
        container
            .read(editPostAttachmentsPersistenceProvider)
            .recordForPost(803),
        isNotNull,
      );
      expect(
        container
            .read(editPostAttachmentsPersistenceProvider)
            .recordForPost(804),
        isNull,
      );
    });

    test('4 sin mezcla entre sesiones', () async {
      final g = FakePostGateway(
        detailById: {
          805: draftPostDetail(
            id: 805,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        uploadThrowsUncertain: true,
      );
      final container = c(g);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(805).future);
      keepAlive(container, 805);
      final snap = EditPostSnapshot.fromDetail(g.detailById![805]!);
      final attach = container.read(
        editPostAttachmentsControllerProvider(805).notifier,
      );
      attach.hydrateFromEditableRevision(
        revisionId: snap.editableRevisionId!,
        serverAttachments: snap.readOnlyAttachments,
      );
      await attach.pickAndAddPdf();
      await attach.uploadPending();
      await container
          .read(authControllerProvider.notifier)
          .logout(localOnly: true);
      expect(
        container
            .read(editPostAttachmentsPersistenceProvider)
            .recordForPost(805),
        isNull,
      );
    });

    test('5 límite de cinco archivos', () {
      final snap = EditPostSnapshot.fromDetail(
        draftWithAttachmentCount(id: 806, count: 5),
      );
      final state = EditPostAttachmentsState(
        serverAttachmentIds: snap.readOnlyAttachments.map((e) => e.id).toList(),
      );
      expect(state.remainingSlots(const []), 0);
    });

    test('6 tamaño máximo', () {
      final err = validatePickedPostAttachmentFile(
        PickedPostFile(
          path: pick.path,
          displayName: 'big.pdf',
          sizeBytes: PostAttachmentLimits.maxSizeBytes + 1,
          mimeType: 'application/pdf',
        ),
        remainingSlots: 1,
      );
      expect(err, isNotNull);
    });

    test('7 MIME permitido', () {
      final err = validatePickedPostAttachmentFile(pick, remainingSlots: 1);
      expect(err, isNull);
    });

    test('8 MIME rechazado', () {
      final err = validatePickedPostAttachmentFile(
        PickedPostFile(
          path: pick.path,
          displayName: 'x.exe',
          sizeBytes: 10,
          mimeType: 'application/x-msdownload',
        ),
        remainingSlots: 1,
      );
      expect(err, isNotNull);
    });

    test('9 upload exitoso', () async {
      final g = FakePostGateway(
        detailById: {
          807: draftPostDetail(
            id: 807,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
      );
      final container = c(g);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(807).future);
      keepAlive(container, 807);
      keepAlive(container, 807);
      final snap = EditPostSnapshot.fromDetail(g.detailById![807]!);
      final attach = container.read(
        editPostAttachmentsControllerProvider(807).notifier,
      );
      attach.hydrateFromEditableRevision(
        revisionId: snap.editableRevisionId!,
        serverAttachments: snap.readOnlyAttachments,
      );
      await attach.pickAndAddPdf();
      final outcome = await attach.uploadPending();
      expect(outcome, isA<EditPostUploadSuccess>());
      expect(g.uploadCallCount, 1);
    });

    test('10 upload 422', () async {
      final g = FakePostGateway(
        detailById: {
          808: draftPostDetail(
            id: 808,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        uploadFailureByPostId: {
          808: const ApiValidationFailure({
            'file': ['x'],
          }),
        },
      );
      final container = c(g);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(808).future);
      keepAlive(container, 808);
      final attach = container.read(
        editPostAttachmentsControllerProvider(808).notifier,
      );
      final snap = EditPostSnapshot.fromDetail(g.detailById![808]!);
      attach.hydrateFromEditableRevision(
        revisionId: snap.editableRevisionId!,
        serverAttachments: snap.readOnlyAttachments,
      );
      await attach.pickAndAddPdf();
      final outcome = await attach.uploadPending();
      expect(outcome, isA<EditPostUploadFailure>());
    });

    test('11 upload 403', () async {
      final g = FakePostGateway(
        detailById: {
          809: draftPostDetail(
            id: 809,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        uploadFailureByPostId: {809: const ApiForbiddenFailure()},
      );
      final container = c(g);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(809).future);
      keepAlive(container, 809);
      final attach = container.read(
        editPostAttachmentsControllerProvider(809).notifier,
      );
      final snap = EditPostSnapshot.fromDetail(g.detailById![809]!);
      attach.hydrateFromEditableRevision(
        revisionId: snap.editableRevisionId!,
        serverAttachments: snap.readOnlyAttachments,
      );
      await attach.pickAndAddPdf();
      expect(await attach.uploadPending(), isA<EditPostUploadFailure>());
    });

    test('12 upload 401', () async {
      final g = FakePostGateway(
        detailById: {
          810: draftPostDetail(
            id: 810,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        uploadFailureByPostId: {810: const ApiSessionExpiredFailure()},
      );
      final container = c(g);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(810).future);
      keepAlive(container, 810);
      final attach = container.read(
        editPostAttachmentsControllerProvider(810).notifier,
      );
      final snap = EditPostSnapshot.fromDetail(g.detailById![810]!);
      attach.hydrateFromEditableRevision(
        revisionId: snap.editableRevisionId!,
        serverAttachments: snap.readOnlyAttachments,
      );
      await attach.pickAndAddPdf();
      expect(await attach.uploadPending(), isA<EditPostUploadFailure>());
    });

    test('13 upload timeout incierto', () async {
      final g = FakePostGateway(
        detailById: {
          811: draftPostDetail(
            id: 811,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        uploadThrowsUncertain: true,
      );
      final container = c(g);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(811).future);
      keepAlive(container, 811);
      final attach = container.read(
        editPostAttachmentsControllerProvider(811).notifier,
      );
      final snap = EditPostSnapshot.fromDetail(g.detailById![811]!);
      attach.hydrateFromEditableRevision(
        revisionId: snap.editableRevisionId!,
        serverAttachments: snap.readOnlyAttachments,
      );
      await attach.pickAndAddPdf();
      expect(await attach.uploadPending(), isA<EditPostUploadUncertain>());
    });

    test('14 network failure incierto', () async {
      final g = FakePostGateway(
        detailById: {
          812: draftPostDetail(
            id: 812,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        uploadFailureByPostId: {812: const ApiNetworkFailure()},
      );
      final container = c(g);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(812).future);
      keepAlive(container, 812);
      final attach = container.read(
        editPostAttachmentsControllerProvider(812).notifier,
      );
      final snap = EditPostSnapshot.fromDetail(g.detailById![812]!);
      attach.hydrateFromEditableRevision(
        revisionId: snap.editableRevisionId!,
        serverAttachments: snap.readOnlyAttachments,
      );
      await attach.pickAndAddPdf();
      expect(await attach.uploadPending(), isA<EditPostUploadUncertain>());
    });

    test('15 upload HTTP 500 incierto', () async {
      final g = FakePostGateway(
        detailById: {
          813: draftPostDetail(
            id: 813,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        uploadFailureByPostId: {813: const ApiServerFailure()},
      );
      final container = c(g);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(813).future);
      keepAlive(container, 813);
      final attach = container.read(
        editPostAttachmentsControllerProvider(813).notifier,
      );
      final snap = EditPostSnapshot.fromDetail(g.detailById![813]!);
      attach.hydrateFromEditableRevision(
        revisionId: snap.editableRevisionId!,
        serverAttachments: snap.readOnlyAttachments,
      );
      await attach.pickAndAddPdf();
      expect(await attach.uploadPending(), isA<EditPostUploadUncertain>());
    });

    test('16 sin reintento automático tras incierto', () async {
      final g = FakePostGateway(
        detailById: {
          814: draftPostDetail(
            id: 814,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        uploadThrowsUncertain: true,
      );
      final container = c(g);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(814).future);
      keepAlive(container, 814);
      final attach = container.read(
        editPostAttachmentsControllerProvider(814).notifier,
      );
      final snap = EditPostSnapshot.fromDetail(g.detailById![814]!);
      attach.hydrateFromEditableRevision(
        revisionId: snap.editableRevisionId!,
        serverAttachments: snap.readOnlyAttachments,
      );
      await attach.pickAndAddPdf();
      await attach.uploadPending();
      g.uploadThrowsUncertain = false;
      final again = await attach.uploadPending();
      expect(again, isA<EditPostUploadIdle>());
      expect(g.uploadCallCount, 1);
    });

    test('17 doble upload bloqueado', () async {
      final g = FakePostGateway(
        detailById: {
          815: draftPostDetail(
            id: 815,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        uploadDelayMs: 100,
      );
      final container = c(g);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(815).future);
      keepAlive(container, 815);
      final attach = container.read(
        editPostAttachmentsControllerProvider(815).notifier,
      );
      final snap = EditPostSnapshot.fromDetail(g.detailById![815]!);
      attach.hydrateFromEditableRevision(
        revisionId: snap.editableRevisionId!,
        serverAttachments: snap.readOnlyAttachments,
      );
      await attach.pickAndAddPdf();
      final f1 = attach.uploadPending();
      final blocked = await attach.uploadPending();
      expect(blocked, isA<EditPostUploadBlocked>());
      await f1;
    });

    test('18 logout durante upload', () async {
      final g = FakePostGateway(
        detailById: {
          816: draftPostDetail(
            id: 816,
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
      await container.read(editPostControllerProvider(816).future);
      keepAlive(container, 816);
      final attach = container.read(
        editPostAttachmentsControllerProvider(816).notifier,
      );
      final snap = EditPostSnapshot.fromDetail(g.detailById![816]!);
      attach.hydrateFromEditableRevision(
        revisionId: snap.editableRevisionId!,
        serverAttachments: snap.readOnlyAttachments,
      );
      await attach.pickAndAddPdf();
      final op = attach.uploadPending();
      await container
          .read(authControllerProvider.notifier)
          .logout(localOnly: true);
      expect(await op, isA<EditPostUploadDiscarded>());
    });

    test('19 cambio remoto a pending bloquea upload', () async {
      final g = FakePostGateway(
        detailById: {
          817: draftPostDetail(
            id: 817,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        uploadThrowsUncertain: true,
      );
      final container = c(g);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(817).future);
      keepAlive(container, 817);
      final attach = container.read(
        editPostAttachmentsControllerProvider(817).notifier,
      );
      final snap = EditPostSnapshot.fromDetail(g.detailById![817]!);
      attach.hydrateFromEditableRevision(
        revisionId: snap.editableRevisionId!,
        serverAttachments: snap.readOnlyAttachments,
      );
      await attach.pickAndAddPdf();
      await attach.uploadPending();
      g.detailById![817] = pendingPostDetail(id: 817);
      final reconcile = await attach.reconcileUploadsFromServer();
      expect(reconcile, isA<EditPostUploadBlocked>());
    });

    test('20 cierre y reapertura restaura incertidumbre', () async {
      final g = FakePostGateway(
        detailById: {
          818: draftPostDetail(
            id: 818,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        uploadThrowsUncertain: true,
      );
      final container = c(g);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(818).future);
      keepAlive(container, 818);
      final attach = container.read(
        editPostAttachmentsControllerProvider(818).notifier,
      );
      final snap = EditPostSnapshot.fromDetail(g.detailById![818]!);
      attach.hydrateFromEditableRevision(
        revisionId: snap.editableRevisionId!,
        serverAttachments: snap.readOnlyAttachments,
      );
      await attach.pickAndAddPdf();
      await attach.uploadPending();
      container.invalidate(editPostAttachmentsControllerProvider(818));
      final restored = container.read(
        editPostAttachmentsControllerProvider(818),
      );
      expect(restored.hasBlockingUncertain, isTrue);
    });

    test('21 upload incierto conserva bloqueo PATCH', () async {
      final g = FakePostGateway(
        detailById: {
          819: draftPostDetail(
            id: 819,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        uploadThrowsUncertain: true,
      );
      final container = c(g);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(819).future);
      keepAlive(container, 819);
      final attach = container.read(
        editPostAttachmentsControllerProvider(819).notifier,
      );
      final snap = EditPostSnapshot.fromDetail(g.detailById![819]!);
      attach.hydrateFromEditableRevision(
        revisionId: snap.editableRevisionId!,
        serverAttachments: snap.readOnlyAttachments,
      );
      await attach.pickAndAddPdf();
      await attach.uploadPending();
      final save = await container
          .read(editPostControllerProvider(819).notifier)
          .save(categoryId: 2, title: 'N', body: 'N');
      expect(save, isA<EditPostSaveBlocked>());
    });

    test('22 GET no limpia incertidumbre sin HTTP 201', () async {
      final g = FakePostGateway(
        detailById: {
          820: draftPostDetail(
            id: 820,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        uploadThrowsUncertain: true,
      );
      final container = c(g);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(820).future);
      keepAlive(container, 820);
      final attach = container.read(
        editPostAttachmentsControllerProvider(820).notifier,
      );
      final snap = EditPostSnapshot.fromDetail(g.detailById![820]!);
      attach.hydrateFromEditableRevision(
        revisionId: snap.editableRevisionId!,
        serverAttachments: snap.readOnlyAttachments,
      );
      await attach.pickAndAddPdf();
      await attach.uploadPending();
      final reconcile = await attach.reconcileUploadsFromServer();
      expect(reconcile, isA<EditPostUploadReconcileInconclusive>());
      expect(
        container
            .read(editPostAttachmentsPersistenceProvider)
            .recordForPost(820)!
            .hasUnresolvedUncertain,
        isTrue,
      );
    });

    test('23 PATCH incierto bloquea upload', () async {
      final g = FakePostGateway(
        detailById: {
          821: draftPostDetail(
            id: 821,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        updateFailureByPostId: {821: const ApiNetworkFailure()},
      );
      final container = c(g);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(821).future);
      keepAlive(container, 821);
      await container
          .read(editPostControllerProvider(821).notifier)
          .save(categoryId: 2, title: 'N', body: 'N');
      final attach = container.read(
        editPostAttachmentsControllerProvider(821).notifier,
      );
      final snap = EditPostSnapshot.fromDetail(g.detailById![821]!);
      attach.hydrateFromEditableRevision(
        revisionId: snap.editableRevisionId!,
        serverAttachments: snap.readOnlyAttachments,
      );
      await attach.pickAndAddPdf();
      expect(await attach.uploadPending(), isA<EditPostUploadBlocked>());
    });

    test('24 upload incierto bloquea PATCH', () async {
      final g = FakePostGateway(
        detailById: {
          822: draftPostDetail(
            id: 822,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
        uploadThrowsUncertain: true,
      );
      final container = c(g);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(822).future);
      keepAlive(container, 822);
      final attach = container.read(
        editPostAttachmentsControllerProvider(822).notifier,
      );
      final snap = EditPostSnapshot.fromDetail(g.detailById![822]!);
      attach.hydrateFromEditableRevision(
        revisionId: snap.editableRevisionId!,
        serverAttachments: snap.readOnlyAttachments,
      );
      await attach.pickAndAddPdf();
      await attach.uploadPending();
      final save = await container
          .read(editPostControllerProvider(822).notifier)
          .save(categoryId: 2, title: 'X', body: 'X');
      expect(save, isA<EditPostSaveBlocked>());
    });

    test('25 sin submit automático', () async {
      final g = FakePostGateway(
        detailById: {
          823: draftPostDetail(
            id: 823,
            groupId: 2,
            categoryId: 2,
            title: 'T',
            body: 'B',
          ),
        },
      );
      final container = c(g);
      addTearDown(container.dispose);
      await container.read(editPostControllerProvider(823).future);
      keepAlive(container, 823);
      final attach = container.read(
        editPostAttachmentsControllerProvider(823).notifier,
      );
      final snap = EditPostSnapshot.fromDetail(g.detailById![823]!);
      attach.hydrateFromEditableRevision(
        revisionId: snap.editableRevisionId!,
        serverAttachments: snap.readOnlyAttachments,
      );
      await attach.pickAndAddPdf();
      await attach.uploadPending();
      expect(g.submitPostCallCount, 0);
    });

    test('26 sin eliminación en servidor', () {
      final item = CreatePostLocalAttachment(
        clientId: 'c1',
        path: pick.path,
        displayName: 'a.pdf',
        sizeBytes: 10,
        mimeType: 'application/pdf',
        state: CreatePostAttachmentState.uploaded,
        serverAttachmentId: 99,
      );
      expect(item.canRemoveLocally, isFalse);
    });

    test('27 sin regresión de creación (smoke)', () async {
      final g = FakePostGateway();
      final container = c(g);
      addTearDown(container.dispose);
      expect(container.read(createPostControllerProvider), isNotNull);
    });

    group('4C.2D.1 cupos y MIME', () {
      test('28 cuatro existentes más dos seleccionados rechaza', () {
        final attach = EditPostAttachmentsState(
          serverAttachmentIds: [1, 2, 3, 4],
          localItems: [
            CreatePostLocalAttachment(
              clientId: 's1',
              path: pick.path,
              displayName: 'a.pdf',
              sizeBytes: 10,
              mimeType: 'application/pdf',
            ),
            CreatePostLocalAttachment(
              clientId: 's2',
              path: pick.path,
              displayName: 'b.pdf',
              sizeBytes: 10,
              mimeType: 'application/pdf',
            ),
          ],
        );
        expect(attach.remainingSlots(const []), 0);
      });

      test('29 cinco existentes más uno seleccionado sin cupo', () {
        final attach = EditPostAttachmentsState(
          serverAttachmentIds: [1, 2, 3, 4, 5],
          localItems: [
            CreatePostLocalAttachment(
              clientId: 's1',
              path: pick.path,
              displayName: 'a.pdf',
              sizeBytes: 10,
              mimeType: 'application/pdf',
            ),
          ],
        );
        expect(attach.remainingSlots(const []), 0);
      });

      test('30 tres + incierto + seleccionado', () {
        final attach = EditPostAttachmentsState(
          serverAttachmentIds: [1, 2, 3],
          localItems: [
            CreatePostLocalAttachment(
              clientId: 'u',
              path: pick.path,
              displayName: 'u.pdf',
              sizeBytes: 10,
              mimeType: 'application/pdf',
              state: CreatePostAttachmentState.uncertain,
            ),
            CreatePostLocalAttachment(
              clientId: 's',
              path: pick.path,
              displayName: 's.pdf',
              sizeBytes: 10,
              mimeType: 'application/pdf',
            ),
          ],
        );
        expect(attach.remainingSlots(const []), 0);
      });

      test('31 cuatro + incierto + seleccionado sin cupo', () {
        final attach = EditPostAttachmentsState(
          serverAttachmentIds: [1, 2, 3, 4],
          localItems: [
            CreatePostLocalAttachment(
              clientId: 'u',
              path: pick.path,
              displayName: 'u.pdf',
              sizeBytes: 10,
              mimeType: 'application/pdf',
              state: CreatePostAttachmentState.uncertain,
            ),
            CreatePostLocalAttachment(
              clientId: 's',
              path: pick.path,
              displayName: 's.pdf',
              sizeBytes: 10,
              mimeType: 'application/pdf',
            ),
          ],
        );
        expect(attach.remainingSlots(const []), 0);
      });

      test('32 exactamente 5 MiB aceptado en validación', () {
        final fiveMiB = 5 * 1024 * 1024;
        final err = validatePickedPostAttachmentFile(
          PickedPostFile(
            path: pick.path,
            displayName: 'big.pdf',
            sizeBytes: fiveMiB,
            mimeType: 'application/pdf',
          ),
          remainingSlots: 1,
        );
        expect(err, isNull);
      });

      test('33 más de 5 MiB rechazado', () {
        final err = validatePickedPostAttachmentFile(
          PickedPostFile(
            path: pick.path,
            displayName: 'big.pdf',
            sizeBytes: 5 * 1024 * 1024 + 1,
            mimeType: 'application/pdf',
          ),
          remainingSlots: 1,
        );
        expect(err, isNotNull);
      });

      test('34 extensión engañosa', () {
        final err = validatePickedPostAttachmentFile(
          PickedPostFile(
            path: pick.path,
            displayName: 'foto.jpg.exe',
            sizeBytes: 10,
            mimeType: 'image/jpeg',
          ),
          remainingSlots: 1,
        );
        expect(err, isNotNull);
      });

      test('35 MIME no detectable', () {
        final err = validatePickedPostAttachmentFile(
          PickedPostFile(
            path: pick.path,
            displayName: 'x.bin',
            sizeBytes: 10,
            mimeType: 'application/octet-stream',
          ),
          remainingSlots: 1,
        );
        expect(err, isNotNull);
      });

      test('36 archivo repetido en selección', () async {
        final g = FakePostGateway(
          detailById: {
            824: draftPostDetail(
              id: 824,
              groupId: 2,
              categoryId: 2,
              title: 'T',
              body: 'B',
            ),
          },
        );
        final container = c(g);
        addTearDown(container.dispose);
        await container.read(editPostControllerProvider(824).future);
        keepAlive(container, 824);
        final attach = container.read(
          editPostAttachmentsControllerProvider(824).notifier,
        );
        final snap = EditPostSnapshot.fromDetail(g.detailById![824]!);
        attach.hydrateFromEditableRevision(
          revisionId: snap.editableRevisionId!,
          serverAttachments: snap.readOnlyAttachments,
        );
        await attach.pickAndAddPdf();
        await attach.pickAndAddPdf();
        expect(
          container.read(editPostAttachmentsControllerProvider(824)).localItems,
          hasLength(2),
        );
      });

      test('37 error 422 cupo servidor', () async {
        final g = FakePostGateway(
          detailById: {825: draftWithAttachmentCount(id: 825, count: 5)},
          uploadFailureByPostId: {
            825: const ApiValidationFailure({
              'file': ['Límite de adjuntos alcanzado'],
            }),
          },
        );
        final container = c(g);
        addTearDown(container.dispose);
        await container.read(editPostControllerProvider(825).future);
        keepAlive(container, 825);
        final attach = container.read(
          editPostAttachmentsControllerProvider(825).notifier,
        );
        final snap = EditPostSnapshot.fromDetail(g.detailById![825]!);
        attach.hydrateFromEditableRevision(
          revisionId: snap.editableRevisionId!,
          serverAttachments: snap.readOnlyAttachments,
        );
        expect(attach.validatePickedFile(pick), isNotNull);
      });
    });
  });
}

PostDetail draftWithAttachmentCount({required int id, required int count}) {
  final json = Map<String, dynamic>.from(sampleCommunityPostJson(id: id));
  json['status'] = 'draft';
  json['content'] = null;
  json['attachments'] = [
    for (var i = 0; i < count; i++)
      {
        'id': 6000 + i,
        'revision_id': id * 10,
        'original_display_name': 'f$i.pdf',
        'mime_type': 'application/pdf',
        'size_bytes': 10,
        'download_url': '/api/v1/posts/$id/attachments/${6000 + i}',
      },
  ];
  json['working_content'] = {'revision_id': id * 10, 'title': 'T', 'body': 'B'};
  return PostDetail.fromJson(json);
}
