import 'package:flutter/material.dart';

import '../../../../core/theme/rv_colors.dart';
import '../chat_labels.dart';

class ChatUnreadBadge extends StatelessWidget {
  const ChatUnreadBadge({required this.count, super.key});

  final int count;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const SizedBox.shrink();
    }
    final compact = compactUnreadCountLabel(count);
    return Semantics(
      label: '$count no leídos',
      excludeSemantics: true,
      child: Container(
        key: ValueKey('chat-unread-count-$count'),
        constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: RvColors.forestGreen,
          borderRadius: BorderRadius.circular(11),
        ),
        child: Text(
          compact,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: RvColors.surfaceWhite,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}
