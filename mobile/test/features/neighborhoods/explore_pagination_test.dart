import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/neighborhoods/application/explore_groups_controller.dart';
import 'package:red_vecinal/features/neighborhoods/data/models/paginated_neighborhood_groups.dart';
import 'package:red_vecinal/features/neighborhoods/data/neighborhood_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'neighborhood_test_support.dart';

void main() {
  ProviderContainer buildContainer(FakeNeighborhoodGateway gateway) {
    return ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        neighborhoodRepositoryProvider.overrideWithValue(gateway),
        authControllerProvider.overrideWith(AuthenticatedBootAuthController.new),
      ],
    );
  }

  PaginatedNeighborhoodGroups page({
    required int page,
    required int last,
    List<int> ids = const [1],
  }) {
    return PaginatedNeighborhoodGroups(
      items: ids.map((id) => sampleNeighborhoodGroup(id: id, name: 'Junta $id')).toList(),
      currentPage: page,
      lastPage: last,
    );
  }

  test('primera página', () async {
    final gateway = FakeNeighborhoodGateway(
      pagesByNumber: {1: page(page: 1, last: 2, ids: [1, 2])},
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    final result = await container.read(exploreGroupsControllerProvider.future);
    expect(result.items, hasLength(2));
    expect(result.hasMore, isTrue);
  });

  test('página siguiente y última página', () async {
    final gateway = FakeNeighborhoodGateway(
      pagesByNumber: {
        1: page(page: 1, last: 2, ids: [1]),
        2: page(page: 2, last: 2, ids: [2]),
      },
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await container.read(exploreGroupsControllerProvider.future);
    await container.read(exploreGroupsControllerProvider.notifier).loadMore();

    final merged = container.read(exploreGroupsControllerProvider).value!;
    expect(merged.items.map((g) => g.id), [1, 2]);
    expect(merged.hasMore, isFalse);
  });

  test('listado vacío', () async {
    final gateway = FakeNeighborhoodGateway(
      pagesByNumber: {1: page(page: 1, last: 1, ids: [])},
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    final result = await container.read(exploreGroupsControllerProvider.future);
    expect(result.items, isEmpty);
    expect(result.hasMore, isFalse);
  });

  test('error en página siguiente conserva página uno', () async {
    final gateway = FakeNeighborhoodGateway(
      pagesByNumber: {1: page(page: 1, last: 2, ids: [1])},
      exploreFailure: const ApiNetworkFailure(),
      exploreFailurePage: 2,
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await container.read(exploreGroupsControllerProvider.future);
    await container.read(exploreGroupsControllerProvider.notifier).loadMore();

    final state = container.read(exploreGroupsControllerProvider).value!;
    expect(state.items, hasLength(1));
    expect(state.hasMore, isTrue);
  });

  test('reintento tras error en página dos', () async {
    final gateway = FakeNeighborhoodGateway(
      pagesByNumber: {1: page(page: 1, last: 2, ids: [1])},
      exploreFailure: const ApiNetworkFailure(),
      exploreFailurePage: 2,
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await container.read(exploreGroupsControllerProvider.future);
    await container.read(exploreGroupsControllerProvider.notifier).loadMore();
    gateway.exploreFailure = null;
    gateway.pagesByNumber = {
      1: page(page: 1, last: 2, ids: [1]),
      2: page(page: 2, last: 2, ids: [2]),
    };

    await container.read(exploreGroupsControllerProvider.notifier).loadMore();
    expect(container.read(exploreGroupsControllerProvider).value!.items.map((g) => g.id), [1, 2]);
  });

  test('respuestas duplicadas no repiten ids', () async {
    final gateway = FakeNeighborhoodGateway(
      pagesByNumber: {
        1: page(page: 1, last: 2, ids: [1, 2]),
        2: page(page: 2, last: 2, ids: [2, 3]),
      },
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await container.read(exploreGroupsControllerProvider.future);
    await container.read(exploreGroupsControllerProvider.notifier).loadMore();

    expect(container.read(exploreGroupsControllerProvider).value!.items.map((g) => g.id), [1, 2, 3]);
  });

  test('loadMore concurrente solo dispara una solicitud', () async {
    final gateway = FakeNeighborhoodGateway(
      exploreListDelayMs: 40,
      pagesByNumber: {
        1: page(page: 1, last: 3, ids: [1]),
        2: page(page: 2, last: 3, ids: [2]),
      },
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await container.read(exploreGroupsControllerProvider.future);
    final before = gateway.callCount;
    final a = container.read(exploreGroupsControllerProvider.notifier).loadMore();
    final b = container.read(exploreGroupsControllerProvider.notifier).loadMore();
    await Future.wait([a, b]);

    expect(gateway.callCount - before, 1);
  });

  test('refresh durante loadMore pendiente no mezcla páginas', () async {
    final gateway = FakeNeighborhoodGateway(
      exploreListDelayMs: 50,
      pagesByNumber: {
        1: page(page: 1, last: 2, ids: [1]),
        2: page(page: 2, last: 2, ids: [2]),
      },
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await container.read(exploreGroupsControllerProvider.future);
    final keepAlive = container.listen(exploreGroupsControllerProvider, (_, __) {});
    final pending = container.read(exploreGroupsControllerProvider.notifier).loadMore();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await container.read(exploreGroupsControllerProvider.notifier).refresh();
    await pending;
    final result = await container.read(exploreGroupsControllerProvider.future);
    keepAlive.close();

    expect(result.items.map((g) => g.id), [1]);
  });
}
