import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/neighborhoods/application/group_membership_review_controller.dart';
import 'package:red_vecinal/features/neighborhoods/application/reviewable_groups_controller.dart';
import 'package:red_vecinal/features/neighborhoods/data/membership_request_repository.dart';
import 'package:red_vecinal/features/neighborhoods/data/models/paginated_neighborhood_groups.dart';

import '../auth/auth_test_support.dart';
import 'membership_request_test_support.dart';
import 'neighborhood_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer membershipContainer(FakeMembershipRequestGateway gateway) {
    return ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        membershipRequestRepositoryProvider.overrideWithValue(gateway),
      ],
    );
  }

  test('approve tardío no afecta sesión nueva', () async {
    final gateway = FakeMembershipRequestGateway(approveDelayMs: 80);
    final container = membershipContainer(gateway);
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    await container.read(groupMembershipReviewControllerProvider(1).future);
    final request = container.read(groupMembershipReviewControllerProvider(1)).value!.items.first;

    final approveFuture =
        container.read(groupMembershipReviewControllerProvider(1).notifier).approve(request);
    await container.read(authControllerProvider.notifier).logout(localOnly: true);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser(id: 2, email: 'b@test.com'));

    final failure = await approveFuture;
    expect(failure, isNull);
    expect(gateway.approveCallCount, 1);
  });

  test('reviewable tardío tras logout', () async {
    final gateway = FakeMembershipRequestGateway(
      reviewableGroupsPage: PaginatedNeighborhoodGroups(
        items: [],
        currentPage: 1,
        lastPage: 1,
      ),
    );
    gateway.reviewableGroupsPage = PaginatedNeighborhoodGroups(
      items: [sampleNeighborhoodGroup(name: 'Vieja')],
      currentPage: 1,
      lastPage: 1,
    );
    final container = membershipContainer(gateway);
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    final keepAlive = container.listen(reviewableGroupsControllerProvider, (_, __) {});
    final stale = container.read(reviewableGroupsControllerProvider.future);
    await container.read(authControllerProvider.notifier).logout(localOnly: true);

    gateway.reviewableGroupsPage = PaginatedNeighborhoodGroups(
      items: [sampleNeighborhoodGroup(name: 'Nueva')],
      currentPage: 1,
      lastPage: 1,
    );

    final page = await stale;
    expect(page.items, isEmpty);
    keepAlive.close();
  });
}
