import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';

import '../auth/auth_test_support.dart';
import '../../test_helpers.dart';

class _ProfileEmptyMunicipalitiesAuth extends AuthController {
  @override
  AuthState build() => AuthAuthenticated(sampleAuthUser(memberships: const []));

  @override
  Future<void> bootstrap() async {}
}

void main() {
  testWidgets('perfil muestra datos de sesión y estado neutral sin municipios', (tester) async {
    await pumpRedVecinalApp(
      tester,
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        authControllerProvider.overrideWith(_ProfileEmptyMunicipalitiesAuth.new),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(navBarIcon(Icons.person_outline));
    await tester.pumpAndSettle();

    expect(find.text('Perfil'), findsWidgets);
    expect(find.text('Vecino Test'), findsOneWidget);
    expect(find.text('vecino@test.com'), findsOneWidget);
    expect(
      find.text('Ninguna municipalidad vinculada a tu cuenta en este perfil.'),
      findsOneWidget,
    );
    expect(find.textContaining('comunidad'), findsNothing);
    expect(find.textContaining('junta'), findsNothing);
    expect(find.byKey(const Key('profile_logout_button')), findsOneWidget);
  });
}
