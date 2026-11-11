import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/data/models/auth_user.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/neighborhoods/application/my_groups_controller.dart';
import 'package:red_vecinal/features/neighborhoods/data/neighborhood_repository.dart';

import '../auth/auth_test_support.dart';
import 'neighborhood_test_support.dart';

class _AuthWithUser extends AuthController {
  _AuthWithUser(this.user);

  final AuthUser user;

  @override
  AuthState build() => AuthAuthenticated(user);
}

void main() {
  ProviderContainer buildContainer(FakeNeighborhoodGateway gateway, {AuthUser? user}) {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        neighborhoodRepositoryProvider.overrideWithValue(gateway),
        authControllerProvider.overrideWith(
          () => _AuthWithUser(user ?? sampleAuthUser(memberships: const [])),
        ),
      ],
    );
    return container;
  }

  test('carga una junta', () async {
    final gateway = FakeNeighborhoodGateway(groups: [sampleNeighborhoodGroup()]);
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    final value = await container.read(myGroupsControllerProvider.future);

    expect(value, hasLength(1));
    expect(gateway.callCount, 1);
  });

  test('carga varias juntas', () async {
    final gateway = FakeNeighborhoodGateway(
      groups: [
        sampleNeighborhoodGroup(id: 1),
        sampleNeighborhoodGroup(id: 2),
      ],
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    expect(await container.read(myGroupsControllerProvider.future), hasLength(2));
  });

  test('lista vacía', () async {
    final container = buildContainer(FakeNeighborhoodGateway());
    addTearDown(container.dispose);

    expect(await container.read(myGroupsControllerProvider.future), isEmpty);
  });

  test('error de conexión', () async {
    final gateway = FakeNeighborhoodGateway(failure: const ApiNetworkFailure());
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await expectLater(
      container.read(myGroupsControllerProvider.future),
      throwsA(isA<ApiNetworkFailure>()),
    );
  });

  test('403 se propaga sin cerrar sesión en repositorio', () async {
    final gateway = FakeNeighborhoodGateway(failure: const ApiForbiddenFailure());
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await expectLater(
      container.read(myGroupsControllerProvider.future),
      throwsA(isA<ApiForbiddenFailure>()),
    );
  });

  test('reintento tras error', () async {
    final gateway = FakeNeighborhoodGateway(failure: const ApiNetworkFailure());
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await expectLater(
      container.read(myGroupsControllerProvider.future),
      throwsA(isA<ApiNetworkFailure>()),
    );

    gateway.failure = null;
    gateway.groups = [sampleNeighborhoodGroup()];

    await container.read(myGroupsControllerProvider.notifier).refresh();

    expect(container.read(myGroupsControllerProvider).value, hasLength(1));
    expect(gateway.callCount, greaterThanOrEqualTo(2));
  });

  test('sin sesión autenticada devuelve lista vacía', () async {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        neighborhoodRepositoryProvider.overrideWithValue(FakeNeighborhoodGateway(
          groups: [sampleNeighborhoodGroup()],
        )),
        authControllerProvider.overrideWith(() => _UnauthBoot()),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(myGroupsControllerProvider.future), isEmpty);
  });

  test('nueva sesión de usuario consulta el gateway de nuevo', () async {
    final gateway = FakeNeighborhoodGateway(groups: [sampleNeighborhoodGroup(id: 1)]);

    final container1 = buildContainer(gateway);
    await container1.read(myGroupsControllerProvider.future);
    container1.dispose();

    gateway.groups = [sampleNeighborhoodGroup(id: 99)];
    final container2 = buildContainer(
      gateway,
      user: AuthUser(
        id: 2,
        name: 'Otro Vecino',
        email: 'otro@test.com',
        municipalityMemberships: const [],
      ),
    );
    addTearDown(container2.dispose);

    final second = await container2.read(myGroupsControllerProvider.future);
    expect(second.single.id, 99);
    expect(gateway.callCount, 2);
  });
}

class _UnauthBoot extends AuthController {
  @override
  AuthState build() => const AuthUnauthenticated();
}
