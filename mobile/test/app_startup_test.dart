import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'features/auth/auth_test_support.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('la aplicación muestra splash y llega al login sin sesión', (tester) async {
    await pumpRedVecinalApp(
      tester,
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      ],
    );

    expect(find.text('Red Vecinal'), findsOneWidget);
    expect(find.text('Iniciando…'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('Acceso vecinal'), findsOneWidget);
    expect(find.text('Iniciar sesión'), findsWidgets);
    expect(find.byKey(const Key('login_submit_button')), findsOneWidget);
  });
}
