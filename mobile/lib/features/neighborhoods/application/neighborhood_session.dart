import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';

int? _sessionEpochFrom(dynamic ref) {
  final auth = ref.read(authControllerProvider);
  if (auth is! AuthAuthenticated) {
    return null;
  }
  return ref.read(authControllerProvider.notifier).sessionEpoch;
}

/// Epoch de sesión vigente mientras el usuario está autenticado; `null` sin sesión.
///
/// Tras operaciones async, si la sesión cambió y el provider aún no se reconstruyó,
/// devuelve `null` en lugar de leer un [Ref] obsoleto.
int? neighborhoodSessionEpoch(dynamic ref) {
  try {
    return _sessionEpochFrom(ref);
  } on Object {
    return null;
  }
}
