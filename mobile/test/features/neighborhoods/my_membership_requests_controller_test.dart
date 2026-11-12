import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/neighborhoods/application/my_membership_requests_controller.dart';
import 'package:red_vecinal/features/neighborhoods/data/membership_request_repository.dart';
import 'package:red_vecinal/features/neighborhoods/data/models/membership_request.dart';
import 'package:red_vecinal/features/neighborhoods/data/models/paginated_membership_requests.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'membership_request_test_support.dart';

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

  test('lista inicial', () async {
    final gateway = FakeMembershipRequestGateway();
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    final page = await container.read(myMembershipRequestsControllerProvider.future);
    expect(page.items, hasLength(1));
  });

  test('paginación conserva página anterior ante error', () async {
    final gateway = FakeMembershipRequestGateway(
      myRequestsPage: const PaginatedMembershipRequests(
        items: [],
        currentPage: 1,
        lastPage: 2,
      ),
    );
    gateway.myRequestsPage = PaginatedMembershipRequests(
      items: [MembershipRequest.fromJson(sampleMembershipRequestJson(id: 1))],
      currentPage: 1,
      lastPage: 2,
    );

    final container = buildContainer(gateway);
    addTearDown(container.dispose);
    await container.read(myMembershipRequestsControllerProvider.future);

    gateway.myRequestsFailure = const ApiNetworkFailure();
    gateway.myRequestsFailurePage = 2;
    gateway.myRequestsPage = const PaginatedMembershipRequests(
      items: [],
      currentPage: 2,
      lastPage: 2,
    );

    await container.read(myMembershipRequestsControllerProvider.notifier).loadMore();
    expect(container.read(myMembershipRequestsControllerProvider).value?.items, hasLength(1));
  });

  test('dedupe en load more', () async {
    final gateway = FakeMembershipRequestGateway(
      myRequestsPagesByNumber: {
        1: PaginatedMembershipRequests(
          items: [MembershipRequest.fromJson(sampleMembershipRequestJson(id: 1))],
          currentPage: 1,
          lastPage: 2,
        ),
        2: PaginatedMembershipRequests(
          items: [
            MembershipRequest.fromJson(sampleMembershipRequestJson(id: 1)),
            MembershipRequest.fromJson(sampleMembershipRequestJson(id: 2, groupId: 2)),
          ],
          currentPage: 2,
          lastPage: 2,
        ),
      },
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);
    await container.read(myMembershipRequestsControllerProvider.future);
    await container.read(myMembershipRequestsControllerProvider.notifier).loadMore();
    expect(container.read(myMembershipRequestsControllerProvider).value?.items.length, 2);
  });

  test('doble load more no dispara segunda carga', () async {
    final gateway = FakeMembershipRequestGateway(
      myRequestsPagesByNumber: {
        1: PaginatedMembershipRequests(
          items: [MembershipRequest.fromJson(sampleMembershipRequestJson(id: 1))],
          currentPage: 1,
          lastPage: 2,
        ),
        2: PaginatedMembershipRequests(
          items: [MembershipRequest.fromJson(sampleMembershipRequestJson(id: 2, groupId: 2))],
          currentPage: 2,
          lastPage: 2,
        ),
      },
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);
    await container.read(myMembershipRequestsControllerProvider.future);

    final notifier = container.read(myMembershipRequestsControllerProvider.notifier);
    final first = notifier.loadMore();
    final second = notifier.loadMore();
    await first;
    await second;

    expect(gateway.myRequestsCallCount, 2);
    expect(container.read(myMembershipRequestsControllerProvider).value?.items.length, 2);
  });

  test('cancelación actualiza estado local', () async {
    final gateway = FakeMembershipRequestGateway();
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await container.read(myMembershipRequestsControllerProvider.future);
    final request = container.read(myMembershipRequestsControllerProvider).value!.items.first;

    final failure = await container
        .read(myMembershipRequestsControllerProvider.notifier)
        .cancelRequest(request);
    expect(failure, isNull);
    expect(
      container.read(myMembershipRequestsControllerProvider).value?.items.first.status,
      'cancelled',
    );
  });
}
