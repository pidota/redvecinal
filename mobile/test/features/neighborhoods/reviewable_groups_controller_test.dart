import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/neighborhoods/application/reviewable_groups_controller.dart';
import 'package:red_vecinal/features/neighborhoods/data/membership_request_repository.dart';
import 'package:red_vecinal/features/neighborhoods/data/models/paginated_neighborhood_groups.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'membership_request_test_support.dart';
import 'neighborhood_test_support.dart';

void main() {
  ProviderContainer buildContainer(FakeMembershipRequestGateway gateway) {
    return ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        membershipRequestRepositoryProvider.overrideWithValue(gateway),
        authControllerProvider.overrideWith(AuthenticatedBootAuthController.new),
      ],
    );
  }

  test('carga juntas revisables', () async {
    final container = buildContainer(FakeMembershipRequestGateway());
    addTearDown(container.dispose);

    final page = await container.read(reviewableGroupsControllerProvider.future);
    expect(page.items, isNotEmpty);
  });

  test('sin juntas revisables', () async {
    final gateway = FakeMembershipRequestGateway(
      reviewableGroupsPage: const PaginatedNeighborhoodGroups(
        items: [],
        currentPage: 1,
        lastPage: 1,
      ),
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    final page = await container.read(reviewableGroupsControllerProvider.future);
    expect(page.items, isEmpty);
  });

  test('paginación dedupe', () async {
    final gateway = FakeMembershipRequestGateway(
      reviewableGroupsPagesByNumber: {
        1: PaginatedNeighborhoodGroups(
          items: [sampleNeighborhoodGroup(id: 1)],
          currentPage: 1,
          lastPage: 2,
        ),
        2: PaginatedNeighborhoodGroups(
          items: [
            sampleNeighborhoodGroup(id: 1),
            sampleNeighborhoodGroup(id: 2, name: 'Dos'),
          ],
          currentPage: 2,
          lastPage: 2,
        ),
      },
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);
    await container.read(reviewableGroupsControllerProvider.future);
    await container.read(reviewableGroupsControllerProvider.notifier).loadMore();
    expect(container.read(reviewableGroupsControllerProvider).value?.items.length, 2);
  });
}
