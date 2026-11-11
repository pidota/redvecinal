import '../data/models/auth_user.dart';

sealed class AuthState {
  const AuthState();
}

final class AuthInitializing extends AuthState {
  const AuthInitializing();
}

final class AuthUnauthenticated extends AuthState {
  const AuthUnauthenticated();
}

final class AuthAuthenticating extends AuthState {
  const AuthAuthenticating();
}

final class AuthAuthenticated extends AuthState {
  const AuthAuthenticated(this.user);

  final AuthUser user;
}

/// Fallo al restaurar sesión (red/servidor): conserva token en almacenamiento.
final class AuthRecoverableError extends AuthState {
  const AuthRecoverableError(this.message);

  final String message;
}
