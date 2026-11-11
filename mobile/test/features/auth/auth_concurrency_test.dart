import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/features/auth/data/models/auth_user.dart';
import 'package:red_vecinal/features/auth/data/models/login_response.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/core/network/session_invalidation_coordinator.dart';
import 'package:red_vecinal/core/network/unauthorized_handler.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/core/storage/token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';

import 'auth_test_support.dart';

class _CountingTokenStorage implements TokenStorage {
  int saveCount = 0;
  int deleteCount = 0;
  String? token;

  @override
  Future<void> deleteToken() async {
    deleteCount++;
    token = null;
  }

  @override
  Future<String?> readToken() async => token;

  @override
  Future<void> saveToken(String value) async {
    saveCount++;
    token = value;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProviderContainer buildContainer({
    required FakeAuthGateway gateway,
    required TokenStorage storage,
  }) {
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(gateway),
        tokenStorageProvider.overrideWithValue(storage),
      ],
    );
    container.read(unauthorizedHandlerProvider.notifier).state =
        () => container.read(authControllerProvider.notifier).onSessionInvalidated();
    return container;
  }

  group('concurrencia de sesión', () {
    test('dos 401 simultáneos invalidan una sola vez', () async {
      var calls = 0;
      final coordinator = SessionInvalidationCoordinator(() async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      await Future.wait([
        coordinator.handleUnauthorized(),
        coordinator.handleUnauthorized(),
      ]);

      expect(calls, 1);
    });

    test('login exitoso no es sobrescrito por bootstrap tardío', () async {
      final gateway = _DelayedMeGateway();
      final storage = _CountingTokenStorage();
      storage.token = '1|old';
      final container = buildContainer(gateway: gateway, storage: storage);
      addTearDown(container.dispose);

      final ctrl = container.read(authControllerProvider.notifier);
      final bootstrapFuture = ctrl.bootstrap();

      await Future<void>.delayed(const Duration(milliseconds: 20));

      gateway.meUser = sampleAuthUser();
      await ctrl.login(email: 'a@b.com', password: 'ok');

      await bootstrapFuture;

      expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
      expect((container.read(authControllerProvider) as AuthAuthenticated).user.name, 'Vecino Test');
    });

    test('bootstrap con error de red no borra token', () async {
      final storage = _CountingTokenStorage()..token = '1|keep';
      final gateway = FakeAuthGateway(meFailure: const ApiNetworkFailure());
      final container = buildContainer(gateway: gateway, storage: storage);
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).bootstrap();

      expect(storage.deleteCount, 0);
      expect(await storage.readToken(), '1|keep');
      expect(container.read(authControllerProvider), isA<AuthRecoverableError>());
    });

    test('403 en gateway no altera estado autenticado', () async {
      final gateway = FakeAuthGateway();
      final container = buildContainer(gateway: gateway, storage: InMemoryTokenStorage());
      addTearDown(container.dispose);

      await container.read(authControllerProvider.notifier).login(
            email: 'a@b.com',
            password: 'ok',
          );

      expect(const ApiForbiddenFailure().userMessage, isNotEmpty);
      expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
    });

    test('logout tardío no borra sesión iniciada después', () async {
      final gateway = _SlowLogoutGateway();
      final storage = _CountingTokenStorage()..token = '1|before';
      final container = buildContainer(gateway: gateway, storage: storage);
      addTearDown(container.dispose);

      final ctrl = container.read(authControllerProvider.notifier);
      await ctrl.bootstrap();

      final logoutFuture = ctrl.logout();

      await Future<void>.delayed(const Duration(milliseconds: 10));

      await ctrl.login(email: 'a@b.com', password: 'ok');

      await logoutFuture;

      expect(container.read(authControllerProvider), isA<AuthAuthenticated>());
      expect(await storage.readToken(), '1|test-token');
    });

    test('logout en curso no deja login colgado en autenticando', () async {
      final gateway = _SlowLoginGateway();
      final container = buildContainer(gateway: gateway, storage: InMemoryTokenStorage());
      addTearDown(container.dispose);

      final ctrl = container.read(authControllerProvider.notifier);
      final loginFuture = ctrl.login(email: 'a@b.com', password: 'ok');

      await Future<void>.delayed(const Duration(milliseconds: 10));
      await ctrl.logout(localOnly: true);

      await loginFuture;

      expect(container.read(authControllerProvider), isA<AuthUnauthenticated>());
    });
  });
}

class _DelayedMeGateway extends FakeAuthGateway {
  _DelayedMeGateway() : super();

  @override
  Future<AuthUser> me() async {
    await Future<void>.delayed(const Duration(milliseconds: 200));
    return meUser ?? sampleAuthUser();
  }
}

class _SlowLoginGateway extends FakeAuthGateway {
  @override
  Future<LoginResponse> login({required String email, required String password}) async {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return sampleLoginResponse();
  }
}

class _SlowLogoutGateway extends FakeAuthGateway {
  @override
  Future<void> logout() async {
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await super.logout();
  }
}
