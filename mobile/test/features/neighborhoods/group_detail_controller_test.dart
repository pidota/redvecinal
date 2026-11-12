import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/neighborhoods/application/group_detail_controller.dart';
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

  test('detalle exitoso', () async {
    final group = sampleNeighborhoodGroup(address: 'Calle 1');
    final gateway = FakeNeighborhoodGateway(groups: [group]);
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    final loaded = await container.read(groupDetailControllerProvider(1).future);
    expect(loaded.name, 'Junta Centro');
    expect(loaded.address, 'Calle 1');
  });

  test('detalle 403', () async {
    final gateway = FakeNeighborhoodGateway(
      groups: [sampleNeighborhoodGroup()],
      detailFailure: const ApiForbiddenFailure(),
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await expectLater(
      container.read(groupDetailControllerProvider(1).future),
      throwsA(isA<ApiForbiddenFailure>()),
    );
  });

  test('detalle 404', () async {
    final gateway = FakeNeighborhoodGateway(
      groups: [sampleNeighborhoodGroup()],
      detailFailure: const ApiNotFoundFailure(),
    );
    final container = buildContainer(gateway);
    addTearDown(container.dispose);

    await expectLater(
      container.read(groupDetailControllerProvider(99).future),
      throwsA(isA<ApiNotFoundFailure>()),
    );
  });
}
