import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/neighborhoods/data/neighborhood_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'neighborhood_test_support.dart';

void main() {
  testWidgets('navega desde Mis juntas al detalle', (tester) async {
    final group = sampleNeighborhoodGroup();
    final gateway = FakeNeighborhoodGateway(groups: [group]);

    await openMainShellAuthenticated(tester, neighborhoodGateway: gateway);
    await tester.tap(navBarIcon(Icons.holiday_village_outlined));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Junta Centro'));
    await tester.pumpAndSettle();

    expect(find.text('Detalle de junta'), findsOneWidget);
    expect(find.text('Descripción', skipOffstage: false), findsWidgets);
  });

  testWidgets('detalle 403 sin cerrar shell', (tester) async {
    final gateway = FakeNeighborhoodGateway(
      groups: [sampleNeighborhoodGroup()],
      detailFailure: const ApiForbiddenFailure('Sin acceso'),
    );

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
    await tester.tap(find.text('Junta Centro'));
    await tester.pumpAndSettle();

    expect(find.text('Acceso denegado'), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
  });

  testWidgets('shell conserva cinco pestañas en hub', (tester) async {
    await openMainShellAuthenticated(tester);
    await tester.tap(navBarIcon(Icons.holiday_village_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Explorar'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('detalle 404 muestra estado sin logout', (tester) async {
    final gateway = FakeNeighborhoodGateway(
      groups: [sampleNeighborhoodGroup()],
      detailFailure: const ApiNotFoundFailure(),
    );

    await openMainShellAuthenticated(tester, neighborhoodGateway: gateway);
    await tester.tap(navBarIcon(Icons.holiday_village_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Junta Centro'));
    await tester.pumpAndSettle();

    expect(find.text('Junta no encontrada'), findsOneWidget);
    expect(find.text('Inicio'), findsNothing);
  });

  testWidgets('ruta inválida sin id numérico', (tester) async {
    await openMainShellAuthenticated(tester);
    final context = tester.element(find.text('Bienvenido a Red Vecinal'));
    GoRouter.of(context).push('/neighborhoods/abc');
    await tester.pumpAndSettle();

    expect(find.text('Ruta no válida'), findsOneWidget);
  });

  testWidgets('explorar muestra indicador miembro', (tester) async {
    final gateway = FakeNeighborhoodGateway(groups: [sampleNeighborhoodGroup()]);

    await openMainShellAuthenticated(tester, neighborhoodGateway: gateway);
    await tester.tap(navBarIcon(Icons.holiday_village_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Explorar'));
    await tester.pumpAndSettle();

    expect(find.text('Miembro'), findsOneWidget);
  });
}
