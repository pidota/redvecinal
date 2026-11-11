import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/domain/auth_state.dart';

/// Notifica a GoRouter cuando cambia el estado de sesión.
class RouterRefreshListenable extends ChangeNotifier {
  RouterRefreshListenable(this._ref) {
    _ref.listen<AuthState>(authControllerProvider, (_, __) {
      notifyListeners();
    });
  }

  final Ref _ref;
}

final routerRefreshListenableProvider = Provider<RouterRefreshListenable>((ref) {
  final listenable = RouterRefreshListenable(ref);
  ref.onDispose(listenable.dispose);
  return listenable;
});
