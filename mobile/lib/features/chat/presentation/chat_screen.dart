import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/feature_shell_scaffold.dart';
import '../../../shared/widgets/rv_empty_state.dart';
import '../../../shared/widgets/rv_loading_indicator.dart';
import '../../../shared/widgets/rv_primary_button.dart';
import '../application/chat_rooms_controller.dart';
import '../data/models/chat_room.dart';
import 'widgets/chat_room_tile.dart';

class ChatScreen extends ConsumerWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomsAsync = ref.watch(chatRoomsControllerProvider);

    return FeatureShellScaffold(
      title: 'Chat',
      phaseLabel: 'Fase 5.5.4',
      body: roomsAsync.when(
        loading: () => const RvLoadingIndicator(message: 'Cargando salas'),
        error: (error, _) => RvEmptyState(
          title: _errorTitle(error),
          message: error is ApiFailure
              ? error.userMessage
              : const ApiUnexpectedFailure().userMessage,
          icon: Icons.cloud_off_outlined,
          action: RvPrimaryButton(
            label: 'Reintentar',
            icon: Icons.refresh,
            onPressed: () =>
                ref.read(chatRoomsControllerProvider.notifier).refresh(),
          ),
        ),
        data: (rooms) {
          if (rooms.isEmpty) {
            return const RvEmptyState(
              title: 'Sin salas',
              message:
                  'No hay salas de chat disponibles con tu membresía activa.',
              icon: Icons.forum_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.read(chatRoomsControllerProvider.notifier).refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.all(RvSpacing.md),
              itemCount: rooms.length,
              separatorBuilder: (_, __) => const SizedBox(height: RvSpacing.sm),
              itemBuilder: (context, index) {
                final room = rooms[index];
                return ChatRoomTile(
                  room: room,
                  onOpen: () => _openRoom(context, room),
                );
              },
            ),
          );
        },
      ),
    );
  }

  void _openRoom(BuildContext context, ChatRoom room) {
    context.push('/chat/${room.id}');
  }

  String _errorTitle(Object error) {
    if (error is ApiSessionExpiredFailure) {
      return 'Sesión no válida';
    }
    if (error is ApiForbiddenFailure) {
      return 'Acceso no disponible';
    }
    return 'No pudimos cargar las salas';
  }
}
