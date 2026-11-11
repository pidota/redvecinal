import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';

import '../../test_helpers.dart';
import 'auth_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('validación de formulario vacío', (tester) async {
    await pumpRedVecinalApp(
      tester,
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      ],
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('login_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('Ingresa tu correo.'), findsOneWidget);
  });

  testWidgets('muestra error 401 de credenciales', (tester) async {
    await pumpRedVecinalApp(
      tester,
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthGateway(loginFailure: const ApiInvalidCredentialsFailure()),
        ),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      ],
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('login_email_field')), 'vecino@test.com');
    await tester.enterText(find.byKey(const Key('login_password_field')), 'bad');
    await tester.tap(find.byKey(const Key('login_submit_button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('credenciales'), findsOneWidget);
  });

  testWidgets('muestra error 429', (tester) async {
    await pumpRedVecinalApp(
      tester,
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthGateway(loginFailure: const ApiRateLimitedFailure()),
        ),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      ],
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('login_email_field')), 'vecino@test.com');
    await tester.enterText(find.byKey(const Key('login_password_field')), 'pass');
    await tester.tap(find.byKey(const Key('login_submit_button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Demasiados intentos'), findsOneWidget);
  });

  testWidgets('error 422 de validación', (tester) async {
    await pumpRedVecinalApp(
      tester,
      overrides: [
        authRepositoryProvider.overrideWithValue(
          FakeAuthGateway(
            loginFailure: const ApiValidationFailure({'email': ['El correo no es válido.']}),
          ),
        ),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
      ],
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('login_email_field')), 'x@y.com');
    await tester.enterText(find.byKey(const Key('login_password_field')), 'pass');
    await tester.tap(find.byKey(const Key('login_submit_button')));
    await tester.pumpAndSettle();

    expect(find.textContaining('correo'), findsWidgets);
  });
}
