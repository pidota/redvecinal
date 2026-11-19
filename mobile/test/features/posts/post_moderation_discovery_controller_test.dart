import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/posts/application/post_moderation_discovery_controller.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

const _groupId = 3;

PostModerationDiscoveryKey _key({String status = 'active'}) {
  return PostModerationDiscoveryKey(groupId: _groupId, groupStatus: status);
}

ProviderContainer discoveryContainer(FakePostGateway gateway) {
  return ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(testAppConfig),
      authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
      tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      postRepositoryProvider.overrideWithValue(gateway),
      authControllerProvider.overrideWith(AuthenticatedBootAuthController.new),
    ],
  );
}

void main() {
  test('presidente/moderador: cola 200 muestra acceso', () async {
    final gateway = FakePostGateway(
      pendingPostsByGroupId: {
        _groupId: const PaginatedFeedPosts(
          items: [],
          currentPage: 1,
          lastPage: 1,
        ),
      },
    );
    final c = discoveryContainer(gateway);
    addTearDown(c.dispose);

    final state = await c.read(
      postModerationDiscoveryControllerProvider(_key()).future,
    );
    expect(state.visibility, PostModerationDiscoveryVisibility.visible);
    expect(gateway.listPendingPostsCallCount, 1);
  });

  test('cola vacía autorizada sigue visible', () async {
    final gateway = FakePostGateway(
      pendingPostsByGroupId: {
        _groupId: const PaginatedFeedPosts(
          items: [],
          currentPage: 1,
          lastPage: 1,
        ),
      },
    );
    final c = discoveryContainer(gateway);
    addTearDown(c.dispose);

    final state = await c.read(
      postModerationDiscoveryControllerProvider(_key()).future,
    );
    expect(state.visibility, PostModerationDiscoveryVisibility.visible);
  });

  test('miembro normal: 403 oculta acceso', () async {
    final gateway = FakePostGateway(
      pendingPostsFailureByGroupId: {_groupId: const ApiForbiddenFailure()},
    );
    final c = discoveryContainer(gateway);
    addTearDown(c.dispose);

    final state = await c.read(
      postModerationDiscoveryControllerProvider(_key()).future,
    );
    expect(state.visibility, PostModerationDiscoveryVisibility.hidden);
  });

  test('404 en cola oculta acceso', () async {
    final gateway = FakePostGateway(
      pendingPostsFailureByGroupId: {_groupId: const ApiNotFoundFailure()},
    );
    final c = discoveryContainer(gateway);
    addTearDown(c.dispose);

    final state = await c.read(
      postModerationDiscoveryControllerProvider(_key()).future,
    );
    expect(state.visibility, PostModerationDiscoveryVisibility.hidden);
  });

  test('junta suspendida no sondea cola', () async {
    final gateway = FakePostGateway(
      pendingPostsByGroupId: {
        _groupId: const PaginatedFeedPosts(
          items: [],
          currentPage: 1,
          lastPage: 1,
        ),
      },
    );
    final c = discoveryContainer(gateway);
    addTearDown(c.dispose);

    final state = await c.read(
      postModerationDiscoveryControllerProvider(
        _key(status: 'suspended'),
      ).future,
    );
    expect(state.visibility, PostModerationDiscoveryVisibility.hidden);
    expect(gateway.listPendingPostsCallCount, 0);
  });

  test('junta inactiva no sondea', () async {
    final gateway = FakePostGateway();
    final c = discoveryContainer(gateway);
    addTearDown(c.dispose);

    await c.read(
      postModerationDiscoveryControllerProvider(
        _key(status: 'inactive'),
      ).future,
    );
    expect(gateway.listPendingPostsCallCount, 0);
  });

  test('sin sesión no sondea', () async {
    final gateway = FakePostGateway(
      pendingPostsByGroupId: {
        _groupId: const PaginatedFeedPosts(
          items: [],
          currentPage: 1,
          lastPage: 1,
        ),
      },
    );
    final c = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        postRepositoryProvider.overrideWithValue(gateway),
        authControllerProvider.overrideWith(_GuestAuth.new),
      ],
    );
    addTearDown(c.dispose);

    final state = await c.read(
      postModerationDiscoveryControllerProvider(_key()).future,
    );
    expect(state.visibility, PostModerationDiscoveryVisibility.hidden);
    expect(gateway.listPendingPostsCallCount, 0);
  });

  test('red no muestra acceso ni asume denegación', () async {
    final gateway = FakePostGateway(
      pendingPostsFailureByGroupId: {_groupId: const ApiNetworkFailure()},
    );
    final c = discoveryContainer(gateway);
    addTearDown(c.dispose);

    final state = await c.read(
      postModerationDiscoveryControllerProvider(_key()).future,
    );
    expect(state.visibility, PostModerationDiscoveryVisibility.hidden);
  });

  test('500 no muestra acceso', () async {
    final gateway = FakePostGateway(
      pendingPostsFailureByGroupId: {_groupId: const ApiUnexpectedFailure()},
    );
    final c = discoveryContainer(gateway);
    addTearDown(c.dispose);

    final state = await c.read(
      postModerationDiscoveryControllerProvider(_key()).future,
    );
    expect(state.visibility, PostModerationDiscoveryVisibility.hidden);
  });

  test('cambio de usuario descarta sondeo tardío', () async {
    final gateway = FakePostGateway(
      pendingPostsDelayMs: 80,
      pendingPostsByGroupId: {
        _groupId: const PaginatedFeedPosts(
          items: [],
          currentPage: 1,
          lastPage: 1,
        ),
      },
    );
    final c = discoveryContainer(gateway);
    addTearDown(c.dispose);

    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(),
    );
    final future = c.read(
      postModerationDiscoveryControllerProvider(_key()).future,
    );
    await c.read(authControllerProvider.notifier).logout(localOnly: true);
    c.read(authControllerProvider.notifier).state = AuthAuthenticated(
      sampleAuthUser(id: 9, email: 'otro@test.com'),
    );
    c.invalidate(postModerationDiscoveryControllerProvider(_key()));

    final fresh = await c.read(
      postModerationDiscoveryControllerProvider(_key()).future,
    );
    expect(fresh.visibility, PostModerationDiscoveryVisibility.visible);
    try {
      await future;
    } on Object {
      // respuesta obsoleta
    }
  });

  test('cambio de rol vía 403 tras invalidar', () async {
    final gateway = FakePostGateway(
      pendingPostsByGroupId: {
        _groupId: const PaginatedFeedPosts(
          items: [],
          currentPage: 1,
          lastPage: 1,
        ),
      },
    );
    final c = discoveryContainer(gateway);
    addTearDown(c.dispose);

    final first = await c.read(
      postModerationDiscoveryControllerProvider(_key()).future,
    );
    expect(first.visibility, PostModerationDiscoveryVisibility.visible);

    gateway.pendingPostsFailureByGroupId = {
      _groupId: const ApiForbiddenFailure(),
    };
    gateway.pendingPostsByGroupId = null;
    c.invalidate(postModerationDiscoveryControllerProvider(_key()));

    final second = await c.read(
      postModerationDiscoveryControllerProvider(_key()).future,
    );
    expect(second.visibility, PostModerationDiscoveryVisibility.hidden);
    expect(gateway.listPendingPostsCallCount, 2);
  });

  test('una sola sondeo por clave de junta activa', () async {
    final gateway = FakePostGateway(
      pendingPostsByGroupId: {
        _groupId: const PaginatedFeedPosts(
          items: [],
          currentPage: 1,
          lastPage: 1,
        ),
      },
    );
    final c = discoveryContainer(gateway);
    addTearDown(c.dispose);

    await c.read(postModerationDiscoveryControllerProvider(_key()).future);
    await c.read(postModerationDiscoveryControllerProvider(_key()).future);
    expect(gateway.listPendingPostsCallCount, 1);
  });
}

class _GuestAuth extends AuthController {
  @override
  AuthState build() => const AuthUnauthenticated();
}
