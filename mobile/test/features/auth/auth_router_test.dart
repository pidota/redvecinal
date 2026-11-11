import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';

import '../../test_helpers.dart';
import 'auth_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sin sesión no muestra contenido del shell', (tester) async {
    await pumpRedVecinalApp(
      tester,
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      ],
    );
    await tester.pumpAndSettle();

    expect(find.text('Bienvenido a Red Vecinal'), findsNothing);
    expect(find.byKey(const Key('login_submit_button')), findsOneWidget);
  });

  testWidgets('con sesión activa llega al inicio', (tester) async {
    await openMainShellAuthenticated(tester);

    expect(find.text('Bienvenido a Red Vecinal'), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
