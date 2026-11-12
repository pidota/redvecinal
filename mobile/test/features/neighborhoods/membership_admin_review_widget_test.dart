import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/neighborhoods/data/membership_request_repository.dart';
import 'package:red_vecinal/features/neighborhoods/data/neighborhood_repository.dart';
import 'package:red_vecinal/features/neighborhoods/data/models/paginated_neighborhood_groups.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'membership_request_test_support.dart';
import 'neighborhood_test_support.dart';

Future<void> openNeighborhoodsWithGateway(
  WidgetTester tester,
  FakeMembershipRequestGateway membershipGateway, {
  FakeNeighborhoodGateway? neighborhoodGateway,
}) async {
  await pumpRedVecinalApp(
    tester,
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
      tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      authControllerProvider.overrideWith(AuthenticatedBootAuthController.new),
      neighborhoodRepositoryProvider.overrideWithValue(
        neighborhoodGateway ?? FakeNeighborhoodGateway(),
      ),
      membershipRequestRepositoryProvider.overrideWithValue(membershipGateway),
    ],
  );
  await tester.pumpAndSettle();
  await tester.tap(navBarIcon(Icons.holiday_village_outlined));
  await tester.pumpAndSettle();
}

void goToRoute(WidgetTester tester, String location) {
  final context = tester.element(find.text('Mis juntas'));
  GoRouter.of(context).go(location);
}

void main() {
  testWidgets('muestra entrada administrativa cuando hay juntas revisables', (tester) async {
    final gateway = FakeMembershipRequestGateway(
      reviewableGroupsPage: PaginatedNeighborhoodGroups(
        items: [sampleNeighborhoodGroup()],
        currentPage: 1,
        lastPage: 1,
      ),
    );

    await openNeighborhoodsWithGateway(tester, gateway);
    expect(find.text('Revisar solicitudes'), findsOneWidget);
  });

  testWidgets('oculta entrada cuando reviewable-groups está vacío', (tester) async {
    final gateway = FakeMembershipRequestGateway(
      reviewableGroupsPage: const PaginatedNeighborhoodGroups(
        items: [],
        currentPage: 1,
        lastPage: 1,
      ),
    );

    await openNeighborhoodsWithGateway(tester, gateway);
    expect(find.text('Revisar solicitudes'), findsNothing);
  });

  testWidgets('navega a bandeja de juntas revisables', (tester) async {
    final gateway = FakeMembershipRequestGateway(
      reviewableGroupsPage: PaginatedNeighborhoodGroups(
        items: [sampleNeighborhoodGroup()],
        currentPage: 1,
        lastPage: 1,
      ),
    );

    await openNeighborhoodsWithGateway(tester, gateway);
    await tester.tap(find.text('Revisar solicitudes'));
    await tester.pumpAndSettle();

    expect(find.text('Revisar solicitudes', skipOffstage: false), findsWidgets);
    expect(find.text('Junta Centro'), findsOneWidget);
  });

  testWidgets('ruta directa review-requests con 403 no muestra pendientes', (tester) async {
    final gateway = FakeMembershipRequestGateway(
      groupRequestsFailure: const ApiForbiddenFailure('No tienes permiso para realizar esta acción.'),
    );

    await openNeighborhoodsWithGateway(tester, gateway);
    goToRoute(tester, '/neighborhoods/99/review-requests');
    await tester.pumpAndSettle();

    expect(find.text('No tienes permiso para realizar esta acción.'), findsOneWidget);
    expect(find.text('Aprobar'), findsNothing);
  });

  testWidgets('ruta directa review sin juntas muestra vacío', (tester) async {
    final gateway = FakeMembershipRequestGateway(
      reviewableGroupsPage: const PaginatedNeighborhoodGroups(
        items: [],
        currentPage: 1,
        lastPage: 1,
      ),
    );

    await openNeighborhoodsWithGateway(tester, gateway);
    goToRoute(tester, '/neighborhoods/review');
    await tester.pumpAndSettle();

    expect(find.text('Sin juntas para revisar'), findsOneWidget);
  });

  testWidgets('nota de revisión limita a 500 caracteres', (tester) async {
    final gateway = FakeMembershipRequestGateway(
      reviewableGroupsPage: PaginatedNeighborhoodGroups(
        items: [sampleNeighborhoodGroup()],
        currentPage: 1,
        lastPage: 1,
      ),
    );

    await openNeighborhoodsWithGateway(tester, gateway);
    goToRoute(tester, '/neighborhoods/1/review-requests');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aprobar'));
    await tester.pumpAndSettle();

    expect(find.text('0/500'), findsOneWidget);
  });

  testWidgets('403 tras aprobar sale del flujo sin mensaje de éxito', (tester) async {
    final gateway = FakeMembershipRequestGateway(
      approveFailure: const ApiForbiddenFailure(),
    );

    await openNeighborhoodsWithGateway(tester, gateway);
    goToRoute(tester, '/neighborhoods/1/review-requests');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aprobar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, aprobar'));
    await tester.pumpAndSettle();

    expect(find.text('Solicitud aprobada.'), findsNothing);
    expect(find.text('Aprobar'), findsNothing);
    expect(find.text('No tienes permiso para realizar esta acción.'), findsOneWidget);
    expect(gateway.reviewableGroupsCallCount, greaterThanOrEqualTo(1));
  });

  testWidgets('confirmación antes de aprobar', (tester) async {
    final gateway = FakeMembershipRequestGateway();

    await openNeighborhoodsWithGateway(tester, gateway);
    goToRoute(tester, '/neighborhoods/1/review-requests');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aprobar'));
    await tester.pumpAndSettle();
    expect(find.text('Aprobar incorporación'), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar aprobación'), findsOneWidget);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(gateway.approveCallCount, 0);
  });

  testWidgets('confirmación antes de rechazar', (tester) async {
    final gateway = FakeMembershipRequestGateway();

    await openNeighborhoodsWithGateway(tester, gateway);
    goToRoute(tester, '/neighborhoods/1/review-requests');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Rechazar'));
    await tester.pumpAndSettle();
    expect(find.text('Rechazar solicitud'), findsOneWidget);
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar rechazo'), findsOneWidget);
    await tester.tap(find.text('No'));
    await tester.pumpAndSettle();
    expect(gateway.rejectCallCount, 0);
  });

  testWidgets('409 no muestra snackbar de éxito', (tester) async {
    final gateway = FakeMembershipRequestGateway(
      approveFailure: const ApiConflictFailure('Solo se pueden aprobar solicitudes pendientes.'),
    );

    await openNeighborhoodsWithGateway(tester, gateway);
    goToRoute(tester, '/neighborhoods/1/review-requests');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aprobar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Continuar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sí, aprobar'));
    await tester.pumpAndSettle();

    expect(find.text('Solicitud aprobada.'), findsNothing);
    expect(find.text('Solo se pueden aprobar solicitudes pendientes.'), findsOneWidget);
  });
}
