import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/posts/application/post_detail_controller.dart';
import 'package:red_vecinal/features/posts/data/post_attachment_storage.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

ProviderContainer detailSessionContainer({
  required FakePostGateway gateway,
  PostAttachmentStorage? storage,
}) {
  return ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(testAppConfig),
      authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
      tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      postRepositoryProvider.overrideWithValue(gateway),
      if (storage != null)
        postAttachmentStorageProvider.overrideWithValue(storage),
    ],
  );
}

void main() {
  test('logout durante carga descarta resultado', () async {
    final gateway = FakePostGateway(detailDelayMs: 80);
    final container = detailSessionContainer(gateway: gateway);
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(),
    );
    final keepAlive = container.listen(
      postDetailControllerProvider(1),
      (_, __) {},
    );
    final futureA = container.read(postDetailControllerProvider(1).future);

    await container
        .read(authControllerProvider.notifier)
        .logout(localOnly: true);

    await expectLater(futureA, throwsA(isA<StateError>()));
    keepAlive.close();
  });

  test('respuesta tardía no actualiza tras cambio de usuario', () async {
    final gateway = FakePostGateway(
      detailDelayMs: 80,
      detailById: {1: sampleCommunityPostDetail(id: 99)},
    );
    final container = detailSessionContainer(gateway: gateway);
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(),
    );
    final keepAlive = container.listen(
      postDetailControllerProvider(1),
      (_, __) {},
    );
    final futureA = container.read(postDetailControllerProvider(1).future);

    await container
        .read(authControllerProvider.notifier)
        .logout(localOnly: true);
    container.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(id: 2, email: 'nuevo@test.com'),
    );

    gateway.detailById = {1: sampleCommunityPostDetail(id: 1)};

    await futureA;
    final detail = await container.read(postDetailControllerProvider(1).future);
    expect(detail.id, 1);
    keepAlive.close();
  });

  test('logout durante descarga cancela entrega', () async {
    final gateway = FakePostGateway(downloadDelayMs: 80);
    final container = detailSessionContainer(gateway: gateway);
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(),
    );

    await container.read(postDetailControllerProvider(1).future);
    final attachment = sampleCommunityPostDetail().attachments.first;
    final futureDownload = container
        .read(postDetailControllerProvider(1).notifier)
        .downloadAttachment(attachment);

    await container
        .read(authControllerProvider.notifier)
        .logout(localOnly: true);

    final result = await futureDownload;
    expect(result.sessionEnded, isTrue);
  });
}
