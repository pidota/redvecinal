import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/application/post_detail_controller.dart';
import 'package:red_vecinal/features/posts/data/post_attachment_storage.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

void main() {
  ProviderContainer buildContainer({
    required FakePostGateway gateway,
    PostAttachmentStorage? storage,
  }) {
    return ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        postRepositoryProvider.overrideWithValue(gateway),
        if (storage != null)
          postAttachmentStorageProvider.overrideWithValue(storage),
        authControllerProvider.overrideWith(
          AuthenticatedBootAuthController.new,
        ),
      ],
    );
  }

  test('carga exitosa de detalle', () async {
    final fake = FakePostGateway(
      detailById: {3: sampleCommunityPostDetail(id: 3)},
    );
    final container = buildContainer(gateway: fake);
    addTearDown(container.dispose);

    final detail = await container.read(postDetailControllerProvider(3).future);
    expect(detail.id, 3);
    expect(fake.detailCallCount, 1);
  });

  test('refresh recarga detalle', () async {
    final fake = FakePostGateway();
    final container = buildContainer(gateway: fake);
    addTearDown(container.dispose);

    await container.read(postDetailControllerProvider(1).future);
    await container.read(postDetailControllerProvider(1).notifier).refresh();
    expect(fake.detailCallCount, greaterThanOrEqualTo(2));
  });

  test('error 404 expuesto en estado async', () async {
    final fake = FakePostGateway(
      detailFailureById: {8: const ApiNotFoundFailure()},
    );
    final container = buildContainer(gateway: fake);
    addTearDown(container.dispose);

    await expectLater(
      container.read(postDetailControllerProvider(8).future),
      throwsA(isA<ApiNotFoundFailure>()),
    );
  });

  test('descarga autenticada guarda en almacén', () async {
    final storage = InMemoryPostAttachmentStorage();
    final fake = FakePostGateway(
      attachmentBytesById: {
        7: [1, 2, 3, 4],
      },
    );
    final container = buildContainer(gateway: fake, storage: storage);
    addTearDown(container.dispose);

    await container.read(postDetailControllerProvider(1).future);
    final epoch = container.read(authControllerProvider.notifier).sessionEpoch;
    storage.activateSession(sessionEpoch: epoch, userId: sampleAuthUser().id);
    final attachment = sampleCommunityPostDetail().attachments.first;
    final result = await container
        .read(postDetailControllerProvider(1).notifier)
        .downloadAttachment(attachment);

    expect(result.savedPath, isNotNull);
    expect(result.sessionEnded, isFalse);
    expect(storage.fileCount, 1);
    expect(fake.downloadCallCount, 1);
  });

  test('descarga fallida propaga error', () async {
    final fake = FakePostGateway(downloadFailure: const ApiForbiddenFailure());
    final container = buildContainer(gateway: fake);
    addTearDown(container.dispose);

    await container.read(postDetailControllerProvider(1).future);
    final attachment = sampleCommunityPostDetail().attachments.first;

    await expectLater(
      container
          .read(postDetailControllerProvider(1).notifier)
          .downloadAttachment(attachment),
      throwsA(isA<ApiForbiddenFailure>()),
    );
  });
}
