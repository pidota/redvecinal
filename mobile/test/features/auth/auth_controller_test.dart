import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_client.dart';
import 'package:red_vecinal/core/network/unauthorized_handler.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/data/models/login_response.dart';
import 'package:red_vecinal/features/auth/data/models/municipality_membership.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/core/storage/token_storage.dart';

import 'auth_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer buildContainer({
    required FakeAuthGateway gateway,
    TokenStorage? storage,
  }) {
    final memory = storage ?? InMemoryTokenStorage();
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(gateway),
        tokenStorageProvider.overrideWithValue(memory),
      ],
    );
    container.read(unauthorizedHandlerProvider.notifier).state =
        () => container.read(authControllerProvider.notifier).onSessionInvalidated();
    return container;
  }

  group('AuthController', () {
    test('login exitoso guarda token y autentica', () async {
      final gateway = FakeAuthGateway();
      final storage = InMemoryTokenStorage();
      final container = buildContainer(gateway: gateway, storage: storage);
      addTearDown(container.dispose);

      final failure = await container.read(authControllerProvider.notifier).login(
            email: 'vecino@test.com',
            password: 'secret',
          );

      expect(failure, isNull);
      expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
      expect(await storage.readToken(), '1|test-token');
      expect(container.read(bearerTokenProvider), '1|test-token');
    });

    test('contraseña incorrecta mantiene no autenticado', () async {
      final gateway = FakeAuthGateway(loginFailure: const ApiInvalidCredentialsFailure());
      final container = buildContainer(gateway: gateway);
      addTearDown(container.dispose);

      final failure = await container.read(authControllerProvider.notifier).login(
            email: 'a@b.com',
            password: 'bad',
          );

      expect(failure, isA<ApiInvalidCredentialsFailure>());
      expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
    });

    test('restauración exitosa con token almacenado', () async {
      final storage = InMemoryTokenStorage();
      await storage.saveToken('1|saved');
      final gateway = FakeAuthGateway(meUser: sampleAuthUser());
      final container = buildContainer(gateway: gateway, storage: storage);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).bootstrap();

      expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
    });

    test('token revocado limpia sesión', () async {
      final storage = InMemoryTokenStorage();
      await storage.saveToken('1|saved');
      final gateway = FakeAuthGateway(meFailure: const ApiSessionExpiredFailure());
      final container = buildContainer(gateway: gateway, storage: storage);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).bootstrap();

      expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
      expect(await storage.readToken(), isNull);
    });

    test('error de red en restauración conserva token', () async {
      final storage = InMemoryTokenStorage();
      await storage.saveToken('1|saved');
      final gateway = FakeAuthGateway(meFailure: const ApiNetworkFailure());
      final container = buildContainer(gateway: gateway, storage: storage);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).bootstrap();

      expect(container.read(authControllerProvider), isA<AuthRecoverableError>());
      expect(await storage.readToken(), '1|saved');
    });

    test('error 500 en restauración conserva token', () async {
      final storage = InMemoryTokenStorage();
      await storage.saveToken('1|saved');
      final gateway = FakeAuthGateway(meFailure: const ApiServerFailure());
      final container = buildContainer(gateway: gateway, storage: storage);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).bootstrap();

      expect(container.read(authControllerProvider), isA<AuthRecoverableError>());
    });

    test('logout exitoso limpia token', () async {
      final gateway = FakeAuthGateway();
      final storage = InMemoryTokenStorage();
      final container = buildContainer(gateway: gateway, storage: storage);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).login(
            email: 'a@b.com',
            password: 'ok',
          );
      final error = await container.read(authControllerProvider.notifier).logout();

      expect(error, isNull);
      expect(gateway.logoutCalls, 1);
      expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
      expect(await storage.readToken(), isNull);
    });

    test('logout sin conexión no borra sesión hasta confirmación local', () async {
      final gateway = FakeAuthGateway(logoutFailure: const ApiNetworkFailure());
      final storage = InMemoryTokenStorage();
      final container = buildContainer(gateway: gateway, storage: storage);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).login(
            email: 'a@b.com',
            password: 'ok',
          );

      final error = await container.read(authControllerProvider.notifier).logout();
      expect(error, isA<ApiNetworkFailure>());
      expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
      expect(await storage.readToken(), isNotNull);

      final localError = await container.read(authControllerProvider.notifier).logout(localOnly: true);
      expect(localError, isNull);
      expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
    });

    test('403 no cierra sesión vía gateway throw', () async {
      final gateway = FakeAuthGateway();
      final container = buildContainer(gateway: gateway);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).login(
            email: 'a@b.com',
            password: 'ok',
          );

      expect(
        const ApiForbiddenFailure().userMessage,
        isNotEmpty,
      );
      expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
    });

    test('usuario con varias municipalidades en login', () async {
      final user = sampleAuthUser(
        memberships: [
          MunicipalityMembership(
            id: 1,
            municipalityId: 1,
            municipality: const MunicipalitySummary(id: 1, name: 'A', slug: 'a'),
            role: 'funcionario',
            status: 'active',
          ),
          MunicipalityMembership(
            id: 2,
            municipalityId: 2,
            municipality: const MunicipalitySummary(id: 2, name: 'B', slug: 'b'),
            role: 'administrador',
            status: 'active',
          ),
        ],
      );
      final gateway = FakeAuthGateway(loginResponse: LoginResponse(token: '1|t', tokenType: 'Bearer', user: user));
      final container = buildContainer(gateway: gateway);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).login(
            email: 'a@b.com',
            password: 'ok',
          );

      final auth = container.read(authControllerProvider) as AuthAuthenticated;
      expect(auth.user.municipalityMemberships, hasLength(2));
    });

    test('onSessionInvalidated limpia sesión una sola vez', () async {
      final gateway = FakeAuthGateway();
      final container = buildContainer(gateway: gateway);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).login(
            email: 'a@b.com',
            password: 'ok',
          );

      final ctrl = container.read(authControllerProvider.notifier);
      await Future.wait([
        ctrl.onSessionInvalidated(),
        ctrl.onSessionInvalidated(),
      ]);

      expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
    });

    test('doble login no incrementa llamadas en paralelo', () async {
      final gateway = FakeAuthGateway();
      final container = buildContainer(gateway: gateway);
      addTearDown(container.dispose);

      final ctrl = container.read(authControllerProvider.notifier);
      final futures = [
        ctrl.login(email: 'a@b.com', password: 'ok'),
        ctrl.login(email: 'a@b.com', password: 'ok'),
      ];
      await Future.wait(futures);

      expect(gateway.loginCalls, 1);
    });
  });
}
