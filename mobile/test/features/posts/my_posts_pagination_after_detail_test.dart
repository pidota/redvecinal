import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/application/my_posts_controller.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'my_posts_controller_test.dart';
import 'post_test_support.dart';

void main() {
  test('volviendo del detalle no fuerza refresh de página 1', () async {
    final gateway = FakePostGateway(
      myPostsByPage: {
        1: minePage(page: 1, last: 2, ids: [1]),
        2: minePage(page: 2, last: 2, ids: [2]),
      },
    );
    final c = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        postRepositoryProvider.overrideWithValue(gateway),
        authControllerProvider.overrideWith(
          AuthenticatedBootAuthController.new,
        ),
      ],
    );
    addTearDown(c.dispose);

    await c.read(myPostsControllerProvider.future);
    await c.read(myPostsControllerProvider.notifier).loadMore();
    final callsAfterPagination = gateway.listMyPostsCallCount;

    expect(c.read(myPostsControllerProvider).value!.items.map((p) => p.id), [
      1,
      2,
    ]);

    await Future<void>.delayed(Duration.zero);
    expect(gateway.listMyPostsCallCount, callsAfterPagination);
  });
}
