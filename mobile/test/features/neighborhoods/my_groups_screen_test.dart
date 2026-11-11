import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/neighborhoods/data/neighborhood_repository.dart';

import '../auth/auth_test_support.dart';
import '../../test_helpers.dart';
import 'neighborhood_test_support.dart';

class _VecinoSinMunicipioAuth extends AuthController {
  @override
  AuthState build() => AuthAuthenticated(sampleAuthUser(memberships: const []));
}

void main() {
  testWidgets('muestra lista con municipio y estado suspendido', (tester) async {
    await openMainShellAuthenticated(
      tester,
      neighborhoodGateway: FakeNeighborhoodGateway(
        groups: [sampleNeighborhoodGroup(status: 'suspended')],
      ),
    );
    await tester.tap(navBarIcon(Icons.holiday_village_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Mis juntas'), findsWidgets);
    expect(find.text('Junta Centro'), findsOneWidget);
    expect(find.text('Chépica'), findsOneWidget);
    expect(find.text('Suspendida'), findsOneWidget);
    expect(find.text('Descripción breve'), findsOneWidget);
  });

  testWidgets('vacío sin membresía municipal pero con junta en API', (tester) async {
    await pumpRedVecinalApp(
      tester,
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        authControllerProvider.overrideWith(_VecinoSinMunicipioAuth.new),
        neighborhoodRepositoryProvider.overrideWithValue(
          FakeNeighborhoodGateway(groups: [sampleNeighborhoodGroup()]),
        ),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(navBarIcon(Icons.holiday_village_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Junta Centro'), findsOneWidget);
    expect(find.text('Chépica'), findsOneWidget);
  });

  testWidgets('estado vacío sin juntas', (tester) async {
    await openMainShellAuthenticated(tester);
    await tester.tap(navBarIcon(Icons.holiday_village_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Sin juntas'), findsOneWidget);
  });

  testWidgets('error de conexión con reintento', (tester) async {
    final gateway = FakeNeighborhoodGateway(failure: const ApiNetworkFailure());

    await pumpRedVecinalApp(
      tester,
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        authControllerProvider.overrideWith(AuthenticatedBootAuthController.new),
        neighborhoodRepositoryProvider.overrideWithValue(gateway),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(navBarIcon(Icons.holiday_village_outlined));
    await tester.pumpAndSettle();

    expect(find.text('No pudimos cargar tus juntas'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);

    gateway.failure = null;
    gateway.groups = [sampleNeighborhoodGroup()];

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(find.text('Junta Centro'), findsOneWidget);
  });
}
