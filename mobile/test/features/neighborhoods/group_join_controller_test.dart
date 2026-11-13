import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/neighborhoods/application/group_join_controller.dart';
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

  test('carga contexto y solicitud existente', () async {
    final gateway = FakeMembershipRequestGateway();
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    final data = await container.read(groupJoinControllerProvider(1).future);
    expect(data.group.id, 1);
    expect(data.existingRequest?.id, 100);
    expect(gateway.lastMyRequestsGroupId, 1);
    expect(gateway.myRequestsCallCount, 1);
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

  test('consulta filtrada en una sola página', () async {
    final gateway = FakeMembershipRequestGateway(
      myRequestsPagesByGroup: {
        '7|1': PaginatedMembershipRequests(
          items: [
            MembershipRequest.fromJson(sampleMembershipRequestJson(id: 101, groupId: 7)),
          ],
          currentPage: 1,
          lastPage: 1,
        ),
      },
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    final data = await container.read(groupJoinControllerProvider(7).future);
    expect(data.existingRequest?.id, 101);
    expect(gateway.myRequestsCallCount, 1);
    expect(gateway.lastMyRequestsGroupId, 7);
  });

  test('historial en junta devuelve la solicitud más reciente', () async {
    final gateway = FakeMembershipRequestGateway(
      myRequestsPagesByGroup: {
        '5|1': PaginatedMembershipRequests(
          items: [
            MembershipRequest.fromJson(
              sampleMembershipRequestJson(id: 10, groupId: 5, status: 'pending'),
            ),
            MembershipRequest.fromJson(
              sampleMembershipRequestJson(id: 9, groupId: 5, status: 'rejected'),
            ),
          ],
          currentPage: 1,
          lastPage: 1,
        ),
      },
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    final data = await container.read(groupJoinControllerProvider(5).future);
    expect(data.existingRequest?.id, 10);
    expect(data.existingRequest?.status, 'pending');
  });

  test('colección vacía para la junta', () async {
    final gateway = FakeMembershipRequestGateway(
      myRequestsPagesByGroup: {
        '8|1': const PaginatedMembershipRequests(items: [], currentPage: 1, lastPage: 1),
      },
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    final data = await container.read(groupJoinControllerProvider(8).future);
    expect(data.existingRequest, isNull);
    expect(gateway.lastMyRequestsGroupId, 8);
  });

  test('mis solicitudes sigue usando listado sin filtro', () async {
    final gateway = FakeMembershipRequestGateway();
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await container.read(myMembershipRequestsControllerProvider.future);
    expect(gateway.lastMyRequestsGroupId, isNull);
  });
}
