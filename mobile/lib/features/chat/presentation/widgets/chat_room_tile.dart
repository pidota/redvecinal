import 'package:flutter/material.dart';

import '../../../../core/theme/rv_colors.dart';
import '../../../../core/theme/rv_spacing.dart';
import '../../../../shared/widgets/rv_card.dart';
import '../../data/models/chat_room.dart';
import '../chat_labels.dart';

class ChatRoomTile extends StatelessWidget {
  const ChatRoomTile({
    required this.room,
    required this.onOpen,
    super.key,
  });

  final ChatRoom room;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final writable = room.status.isWritable;
    final title = chatRoomTitle(room);
    return RvCard(
      onTap: onOpen,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            writable ? Icons.forum_outlined : Icons.lock_outline,
            color: writable ? RvColors.forestGreen : RvColors.textMuted,
            semanticLabel: writable ? 'Acceso de lectura y escritura' : 'Solo lectura',
          ),
          const SizedBox(width: RvSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: RvSpacing.xs),
                Text(
                  'Sala ${room.id} · ${chatRoomTypeLabel(room)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: RvColors.textMuted,
                      ),
                ),
                const SizedBox(height: RvSpacing.xs),
                Text(
                  chatRoomStatusLabel(room),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: writable ? RvColors.forestGreen : RvColors.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: RvColors.textMuted),
        ],
      ),
    );
  }
}
