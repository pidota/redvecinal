import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/neighborhoods/application/group_join_controller.dart';
import 'package:red_vecinal/features/neighborhoods/application/my_membership_requests_controller.dart';
import 'package:red_vecinal/features/neighborhoods/data/membership_request_repository.dart';
import 'package:red_vecinal/features/neighborhoods/data/models/membership_request.dart';
import 'package:red_vecinal/features/neighborhoods/data/models/paginated_membership_requests.dart';

import '../auth/auth_test_support.dart';
import 'membership_request_test_support.dart';

ProviderContainer membershipSessionContainer(FakeMembershipRequestGateway gateway) {
  return ProviderContainer(
    overrides: [
      appConfigProvider.overrideWithValue(testAppConfig),
      authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
      tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      membershipRequestRepositoryProvider.overrideWithValue(gateway),
    ],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('submit tardío no actualiza sesión nueva', () async {
    final gateway = FakeMembershipRequestGateway(
      myRequestsPage: const PaginatedMembershipRequests(
        items: [],
        currentPage: 1,
        lastPage: 1,
      ),
      submitDelayMs: 80,
    );
    final container = membershipSessionContainer(gateway);
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    await container.read(groupJoinControllerProvider(2).future);

    final submitFuture =
        container.read(groupJoinControllerProvider(2).notifier).submit();
    await container.read(authControllerProvider.notifier).logout(localOnly: true);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser(id: 2, email: 'b@test.com'));

    final failure = await submitFuture;
    expect(failure, isNull);

    final data = await container.read(groupJoinControllerProvider(2).future);
    expect(data.existingRequest, isNull);
    expect(gateway.submitCallCount, 1);
  });

  test('carga join tardía no pisa sesión nueva', () async {
    final gateway = FakeMembershipRequestGateway(
      contextDelayMs: 80,
      myRequestsPagesByNumber: {
        1: PaginatedMembershipRequests(
          items: [
            MembershipRequest.fromJson(
              sampleMembershipRequestJson(id: 1, groupId: 3, status: 'pending'),
            ),
          ],
          currentPage: 1,
          lastPage: 1,
        ),
      },
    );
    final container = membershipSessionContainer(gateway);
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    final keepAlive = container.listen(groupJoinControllerProvider(3), (_, __) {});
    final stale = container.read(groupJoinControllerProvider(3).future);
    await container.read(authControllerProvider.notifier).logout(localOnly: true);

    gateway.myRequestsPagesByNumber = {
      1: PaginatedMembershipRequests(
        items: [
          MembershipRequest.fromJson(
            sampleMembershipRequestJson(id: 99, groupId: 3, status: 'approved'),
          ),
        ],
        currentPage: 1,
        lastPage: 1,
      ),
    };

    try {
      await stale;
    } on Object {
      // Esperado si la sesión cambió durante la carga.
    }
    keepAlive.close();

    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser(id: 2, email: 'b@test.com'));
    container.invalidate(groupJoinControllerProvider(3));

    final fresh = await container.read(groupJoinControllerProvider(3).future);
    expect(fresh.existingRequest?.status, 'approved');
    expect(fresh.existingRequest?.id, 99);
  });

  test('mis solicitudes: respuesta tardía tras logout se descarta', () async {
    final gateway = FakeMembershipRequestGateway(myRequestsDelayMs: 80);
    final container = membershipSessionContainer(gateway);
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    final keepAlive =
        container.listen(myMembershipRequestsControllerProvider, (_, __) {});
    final stale = container.read(myMembershipRequestsControllerProvider.future);
    await container.read(authControllerProvider.notifier).logout(localOnly: true);

    gateway.myRequestsPage = const PaginatedMembershipRequests(
      items: [],
      currentPage: 1,
      lastPage: 1,
    );

    final page = await stale;
    expect(page.items, isEmpty);
    keepAlive.close();
  });

  test('cancelación tardía no modifica listado de otra sesión', () async {
    final gateway = FakeMembershipRequestGateway();
    final container = membershipSessionContainer(gateway);
    addTearDown(container.dispose);

    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    await container.read(myMembershipRequestsControllerProvider.future);
    final request =
        container.read(myMembershipRequestsControllerProvider).value!.items.first;

    gateway.myRequestsDelayMs = 80;
    final cancelFuture = container
        .read(myMembershipRequestsControllerProvider.notifier)
        .cancelRequest(request);
    await container.read(authControllerProvider.notifier).logout(localOnly: true);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser(id: 2, email: 'b@test.com'));
    container.invalidate(myMembershipRequestsControllerProvider);

    final cancelFailure = await cancelFuture;
    expect(cancelFailure, isNull);

    final page = await container.read(myMembershipRequestsControllerProvider.future);
    expect(page.items.first.status, 'pending');
  });
}
