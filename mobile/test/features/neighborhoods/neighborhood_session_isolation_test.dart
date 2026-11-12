import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/network/unauthorized_handler.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/neighborhoods/application/explore_groups_controller.dart';
import 'package:red_vecinal/features/neighborhoods/application/group_detail_controller.dart';
import 'package:red_vecinal/features/neighborhoods/application/my_groups_controller.dart';
import 'package:red_vecinal/features/neighborhoods/data/models/paginated_neighborhood_groups.dart';
import 'package:red_vecinal/features/neighborhoods/data/neighborhood_repository.dart';

import '../auth/auth_test_support.dart';
import 'neighborhood_test_support.dart';

ProviderContainer sessionContainer(FakeNeighborhoodGateway gateway) {
  final container = ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(testAppConfig),
      authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
      tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      neighborhoodRepositoryProvider.overrideWithValue(gateway),
    ],
  );
  container.read(unauthorizedHandlerProvider.notifier).state =
      () => container.read(authControllerProvider.notifier).onSessionInvalidated();
  return container;
}

void main() {
  test('logout vacía explore y my groups', () async {
    final gateway = FakeNeighborhoodGateway(
      groups: [sampleNeighborhoodGroup()],
      explorePage: PaginatedNeighborhoodGroups(
        items: [sampleNeighborhoodGroup()],
        currentPage: 1,
        lastPage: 1,
      ),
    );
    final container = sessionContainer(gateway);
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).state = AuthAuthenticated(sampleAuthUser());
    await container.read(exploreGroupsControllerProvider.future);
    await container.read(myGroupsControllerProvider.future);

    await container.read(authControllerProvider.notifier).logout(localOnly: true);

    final explore = await container.read(exploreGroupsControllerProvider.future);
    final mine = await container.read(myGroupsControllerProvider.future);
    expect(explore.items, isEmpty);
    expect(mine, isEmpty);
  });

  test('cambio de usuario no reutiliza explore anterior', () async {
    final gateway = FakeNeighborhoodGateway(
      pagesByNumber: {
        1: PaginatedNeighborhoodGroups(
          items: [sampleNeighborhoodGroup(name: 'Junta usuario A')],
          currentPage: 1,
          lastPage: 1,
        ),
      },
    );
    final container = sessionContainer(gateway);
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).state = AuthAuthenticated(sampleAuthUser());
    final first = await container.read(exploreGroupsControllerProvider.future);
    expect(first.items.single.name, 'Junta usuario A');

    gateway.pagesByNumber = {
      1: PaginatedNeighborhoodGroups(
        items: [sampleNeighborhoodGroup(name: 'Junta usuario B')],
        currentPage: 1,
        lastPage: 1,
      ),
    };
  container.invalidate(exploreGroupsControllerProvider);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser(id: 2, email: 'b@test.com'));

    final second = await container.read(exploreGroupsControllerProvider.future);
    expect(second.items.single.name, 'Junta usuario B');
  });

  test('respuesta tardía de explore no pisa sesión nueva', () async {
    final gateway = FakeNeighborhoodGateway(
      exploreListDelayMs: 80,
      explorePage: PaginatedNeighborhoodGroups(
        items: [sampleNeighborhoodGroup(name: 'Viejo')],
        currentPage: 1,
        lastPage: 1,
      ),
    );
    final container = sessionContainer(gateway);
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).state = AuthAuthenticated(sampleAuthUser());
    final keepAlive = container.listen(exploreGroupsControllerProvider, (_, __) {});
    final stale = container.read(exploreGroupsControllerProvider.future);
    await container.read(authControllerProvider.notifier).logout(localOnly: true);

    gateway.explorePage = PaginatedNeighborhoodGroups(
      items: [sampleNeighborhoodGroup(name: 'Nuevo')],
      currentPage: 1,
      lastPage: 1,
    );
    try {
      await stale;
    } on Object {
      // Respuesta descartada tras logout.
    }
    keepAlive.close();

    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser(id: 2, email: 'b@test.com'));
    container.invalidate(exploreGroupsControllerProvider);

    final fresh = await container.read(exploreGroupsControllerProvider.future);
    expect(fresh.items.single.name, 'Nuevo');
  });

  test('nueva sesión recarga detalle sin datos anteriores', () async {
    final gateway = FakeNeighborhoodGateway(groups: [sampleNeighborhoodGroup()]);
    final container = sessionContainer(gateway);
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).state = AuthAuthenticated(sampleAuthUser());
    final first = await container.read(groupDetailControllerProvider(1).future);
    expect(first.name, 'Junta Centro');

    await container.read(authControllerProvider.notifier).logout(localOnly: true);
    gateway.details[1] = sampleNeighborhoodGroup(id: 1, name: 'Junta nueva sesión');
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser(id: 2, email: 'b@test.com'));

    final fresh = await container.read(groupDetailControllerProvider(1).future);
    expect(fresh.name, 'Junta nueva sesión');
  });

  test('403 en detalle no cambia auth', () async {
    final gateway = FakeNeighborhoodGateway(
      groups: [sampleNeighborhoodGroup()],
      detailFailure: const ApiForbiddenFailure(),
    );
    final container = sessionContainer(gateway);
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).state = AuthAuthenticated(sampleAuthUser());
    await expectLater(
      container.read(groupDetailControllerProvider(1).future),
      throwsA(isA<ApiForbiddenFailure>()),
    );
    expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
  });

  test('cambio de sesión durante paginación reinicia desde página uno', () async {
    final gateway = FakeNeighborhoodGateway(
      exploreListDelayMs: 60,
      pagesByNumber: {
        1: PaginatedNeighborhoodGroups(
          items: [sampleNeighborhoodGroup(id: 1)],
          currentPage: 1,
          lastPage: 2,
        ),
        2: PaginatedNeighborhoodGroups(
          items: [sampleNeighborhoodGroup(id: 2)],
          currentPage: 2,
          lastPage: 2,
        ),
      },
    );
    final container = sessionContainer(gateway);
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).state = AuthAuthenticated(sampleAuthUser());
    await container.read(exploreGroupsControllerProvider.future);
    final pending = container.read(exploreGroupsControllerProvider.notifier).loadMore();

    await container.read(authControllerProvider.notifier).logout(localOnly: true);
    gateway.pagesByNumber = {
      1: PaginatedNeighborhoodGroups(
        items: [sampleNeighborhoodGroup(id: 99, name: 'Solo nueva sesión')],
        currentPage: 1,
        lastPage: 1,
      ),
    };
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser(id: 2, email: 'b@test.com'));
    container.invalidate(exploreGroupsControllerProvider);

    await pending;
    final page = await container.read(exploreGroupsControllerProvider.future);
    expect(page.items.single.id, 99);
  });
}
