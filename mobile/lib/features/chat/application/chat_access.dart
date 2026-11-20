import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';

/// Salas con 403 en la sesión actual. Se vacía al cambiar la autenticación.
final chatRevokedRoomIdsProvider = StateProvider<Set<int>>((ref) {
  ref.watch(authControllerProvider);
  return {};
});

void revokeChatRoomAccess(dynamic ref, int roomId) {
  final current = ref.read(chatRevokedRoomIdsProvider);
  ref.read(chatRevokedRoomIdsProvider.notifier).state = <int>{...current, roomId};
}
