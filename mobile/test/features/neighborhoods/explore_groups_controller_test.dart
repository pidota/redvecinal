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
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        neighborhoodRepositoryProvider.overrideWithValue(gateway),
        authControllerProvider.overrideWith(AuthenticatedBootAuthController.new),
      ],
    );
    return container;
  }

  test('listado exitoso', () async {
    final gateway = FakeNeighborhoodGateway(
      groups: [sampleNeighborhoodGroup()],
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    final page = await container.read(exploreGroupsControllerProvider.future);
    expect(page.items, hasLength(1));
  });

  test('listado vacío', () async {
    final gateway = FakeNeighborhoodGateway(
      explorePage: const PaginatedNeighborhoodGroups(items: [], currentPage: 1, lastPage: 1),
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    expect(
      (await container.read(exploreGroupsControllerProvider.future)).items,
      isEmpty,
    );
  });

  test('error de red', () async {
    final gateway = FakeNeighborhoodGateway(exploreFailure: const ApiNetworkFailure());
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await expectLater(
      container.read(exploreGroupsControllerProvider.future),
      throwsA(isA<ApiNetworkFailure>()),
    );
  });

  test('reintento tras error', () async {
    final gateway = FakeNeighborhoodGateway(exploreFailure: const ApiNetworkFailure());
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await expectLater(
      container.read(exploreGroupsControllerProvider.future),
      throwsA(isA<ApiNetworkFailure>()),
    );

    gateway.exploreFailure = null;
    gateway.explorePage = PaginatedNeighborhoodGroups(
      items: [sampleNeighborhoodGroup()],
      currentPage: 1,
      lastPage: 1,
    );

    await container.read(exploreGroupsControllerProvider.notifier).refresh();
    expect(container.read(exploreGroupsControllerProvider).value?.items, hasLength(1));
  });
}
