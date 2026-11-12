import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/neighborhoods/application/group_membership_review_controller.dart';
import 'package:red_vecinal/features/neighborhoods/application/reviewable_groups_controller.dart';
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

  test('lista pendientes por junta', () async {
    final container = buildContainer(FakeMembershipRequestGateway());
    addTearDown(container.dispose);

    final page = await container.read(groupMembershipReviewControllerProvider(1).future);
    expect(page.items.single.isPending, isTrue);
  });

  test('aprobar refresca lista', () async {
    final gateway = FakeMembershipRequestGateway(
      groupRequestsPagesByNumber: {
        '1|pending|1': PaginatedMembershipRequests(
          items: [
            MembershipRequest.fromJson(sampleMembershipRequestJson(id: 20, groupId: 1)),
          ],
          currentPage: 1,
          lastPage: 1,
        ),
        '1|pending|1_after': const PaginatedMembershipRequests(
          items: [],
          currentPage: 1,
          lastPage: 1,
        ),
      },
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await container.read(groupMembershipReviewControllerProvider(1).future);
    final request = container.read(groupMembershipReviewControllerProvider(1)).value!.items.first;
    gateway.groupRequestsPagesByNumber = {
      '1|pending|1': const PaginatedMembershipRequests(items: [], currentPage: 1, lastPage: 1),
    };

    final failure = await container
        .read(groupMembershipReviewControllerProvider(1).notifier)
        .approve(request);
    expect(failure, isNull);
    expect(gateway.approveCallCount, 1);
    expect(container.read(groupMembershipReviewControllerProvider(1)).value?.items, isEmpty);
  });

  test('409 en aprobar devuelve conflicto', () async {
    final gateway = FakeMembershipRequestGateway(
      approveFailure: const ApiConflictFailure('Ya resuelta'),
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await container.read(groupMembershipReviewControllerProvider(1).future);
    final request = container.read(groupMembershipReviewControllerProvider(1)).value!.items.first;
    final failure = await container
        .read(groupMembershipReviewControllerProvider(1).notifier)
        .approve(request);
    expect(failure, isA<ApiConflictFailure>());
  });

  test('403 al aprobar refresca juntas revisables', () async {
    final gateway = FakeMembershipRequestGateway(
      approveFailure: const ApiForbiddenFailure(),
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await container.read(groupMembershipReviewControllerProvider(1).future);
    final request = container.read(groupMembershipReviewControllerProvider(1)).value!.items.first;
    final failure = await container
        .read(groupMembershipReviewControllerProvider(1).notifier)
        .approve(request);
    expect(failure, isA<ApiForbiddenFailure>());
    expect(container.read(groupMembershipReviewControllerProvider(1)).hasError, isTrue);
    await container.read(reviewableGroupsControllerProvider.future);
    expect(gateway.reviewableGroupsCallCount, greaterThanOrEqualTo(1));
  });

  test('timeout al aprobar no refresca como éxito', () async {
    final gateway = FakeMembershipRequestGateway(
      approveFailure: const ApiTimeoutFailure(),
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await container.read(groupMembershipReviewControllerProvider(1).future);
    final before = container.read(groupMembershipReviewControllerProvider(1)).value!.items.length;
    final request = container.read(groupMembershipReviewControllerProvider(1)).value!.items.first;
    final failure = await container
        .read(groupMembershipReviewControllerProvider(1).notifier)
        .approve(request);
    expect(failure, isA<ApiTimeoutFailure>());
    expect(
      container.read(groupMembershipReviewControllerProvider(1)).value!.items.length,
      before,
    );
  });

  test('403 al listar pendientes', () async {
    final gateway = FakeMembershipRequestGateway(
      groupRequestsFailure: const ApiForbiddenFailure(),
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await expectLater(
      container.read(groupMembershipReviewControllerProvider(1).future),
      throwsA(isA<ApiForbiddenFailure>()),
    );
  });
}
