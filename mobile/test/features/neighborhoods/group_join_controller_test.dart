import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/neighborhoods/application/group_join_controller.dart';
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

  test('carga contexto y solicitud existente', () async {
    final gateway = FakeMembershipRequestGateway();
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    final data = await container.read(groupJoinControllerProvider(1).future);
    expect(data.group.id, 1);
    expect(data.existingRequest?.id, 100);
  });

  test('submit válido', () async {
    final gateway = FakeMembershipRequestGateway(
      myRequestsPage: const PaginatedMembershipRequests(
        items: [],
        currentPage: 1,
        lastPage: 1,
      ),
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await container.read(groupJoinControllerProvider(2).future);
    final failure = await container.read(groupJoinControllerProvider(2).notifier).submit();
    expect(failure, isNull);
    expect(gateway.submitCallCount, 1);
    expect(
      container.read(groupJoinControllerProvider(2)).value?.existingRequest?.status,
      'pending',
    );
  });

  test('409 refresca estado', () async {
    final gateway = FakeMembershipRequestGateway(
      myRequestsPage: const PaginatedMembershipRequests(
        items: [],
        currentPage: 1,
        lastPage: 1,
      ),
      submitFailure: const ApiConflictFailure('Ya tienes una solicitud pendiente para esta junta.'),
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await container.read(groupJoinControllerProvider(1).future);
    final failure = await container.read(groupJoinControllerProvider(1).notifier).submit();
    expect(failure, isA<ApiConflictFailure>());
    expect(gateway.submitCallCount, 1);
  });

  test('encuentra solicitud existente en página 2', () async {
    final gateway = FakeMembershipRequestGateway(
      myRequestsPagesByNumber: {
        1: PaginatedMembershipRequests(
          items: [
            MembershipRequest.fromJson(sampleMembershipRequestJson(id: 50, groupId: 99)),
          ],
          currentPage: 1,
          lastPage: 2,
        ),
        2: PaginatedMembershipRequests(
          items: [
            MembershipRequest.fromJson(sampleMembershipRequestJson(id: 101, groupId: 7)),
          ],
          currentPage: 2,
          lastPage: 2,
        ),
      },
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    final data = await container.read(groupJoinControllerProvider(7).future);
    expect(data.existingRequest?.id, 101);
  });
}
