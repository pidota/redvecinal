import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';

/// Epoch de sesión vigente mientras el usuario está autenticado; `null` sin sesión.
int? neighborhoodSessionEpoch(Ref ref) {
  final auth = ref.read(authControllerProvider);
  if (auth is! AuthAuthenticated) {
    return null;
  }
  return ref.read(authControllerProvider.notifier).sessionEpoch;
}
