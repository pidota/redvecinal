import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/unauthorized_handler.dart';
import '../../../core/network/api_failure.dart';
import '../../../core/storage/secure_token_storage.dart';
import '../data/auth_repository.dart';
import '../data/models/auth_user.dart';
import '../domain/auth_state.dart';

class AuthController extends Notifier<AuthState> {
  bool _bootstrapStarted = false;
  bool _loggingOut = false;
  bool _loginInFlight = false;
  int _sessionEpoch = 0;

  @override
  AuthState build() => const AuthInitializing();

  Future<void> bootstrap() async {
    if (_bootstrapStarted) {
      return;
    }
    _bootstrapStarted = true;
    ref.read(unauthorizedHandlerProvider.notifier).state = onSessionInvalidated;
    state = const AuthInitializing();

    final storage = ref.read(tokenStorageProvider);
    final token = await storage.readToken();

    if (token == null || token.isEmpty) {
      _clearBearer();
      state = const AuthUnauthenticated();
      return;
    }

    _setBearer(token);
    final restoreEpoch = _sessionEpoch;

    try {
      final user = await ref.read(authRepositoryProvider).me();
      if (restoreEpoch != _sessionEpoch) {
        return;
      }
      state = AuthAuthenticated(user);
    } on ApiSessionExpiredFailure {
      if (restoreEpoch != _sessionEpoch) {
        return;
      }
      await _clearSessionLocal();
      state = const AuthUnauthenticated();
    } on ApiFailure catch (e) {
      if (restoreEpoch != _sessionEpoch) {
        return;
      }
      state = AuthRecoverableError(e.userMessage);
    }
  }

  Future<ApiFailure?> login({
    required String email,
    required String password,
  }) async {
    if (_loginInFlight) {
      return null;
    }
    _loginInFlight = true;
    _sessionEpoch++;
    final loginEpoch = _sessionEpoch;
    state = const AuthAuthenticating();

    try {
      final result = await ref.read(authRepositoryProvider).login(
            email: email,
            password: password,
          );

      if (loginEpoch != _sessionEpoch) {
        return null;
      }

      final storage = ref.read(tokenStorageProvider);
      await storage.saveToken(result.token);
      _setBearer(result.token);
      state = AuthAuthenticated(result.user);
      return null;
    } on ApiFailure catch (e) {
      state = const AuthUnauthenticated();
      return e;
    } finally {
      _loginInFlight = false;
    }
  }

  Future<void> retryRestoreSession() async {
    _bootstrapStarted = false;
    await bootstrap();
  }

  Future<ApiFailure?> logout({bool localOnly = false}) async {
    if (_loggingOut) {
      return null;
    }
    _loggingOut = true;
    final logoutEpoch = _sessionEpoch;

    try {
      if (!localOnly) {
        try {
          await ref.read(authRepositoryProvider).logout();
        } on ApiNetworkFailure catch (e) {
          return e;
        } on ApiTimeoutFailure catch (e) {
          return e;
        } on ApiFailure catch (_) {
          // Revocación remota fallida: igualmente cerramos en el dispositivo.
        }
      }

      if (logoutEpoch != _sessionEpoch) {
        return null;
      }

      _sessionEpoch++;
      await _clearSessionLocal();
      state = const AuthUnauthenticated();
      return null;
    } finally {
      _loggingOut = false;
    }
  }

  Future<void> onSessionInvalidated() async {
    if (_loggingOut || state is AuthUnauthenticated || _loginInFlight) {
      return;
    }
    _sessionEpoch++;
    await _clearSessionLocal();
    state = const AuthUnauthenticated();
  }

  Future<void> _clearSessionLocal() async {
    await ref.read(tokenStorageProvider).deleteToken();
    _clearBearer();
  }

  void _setBearer(String token) {
    ref.read(bearerTokenProvider.notifier).state = token;
  }

  void _clearBearer() {
    ref.read(bearerTokenProvider.notifier).state = null;
  }

  AuthUser? get currentUser {
    final s = state;
    if (s is AuthAuthenticated) {
      return s.user;
    }
    return null;
  }
}

final authControllerProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
