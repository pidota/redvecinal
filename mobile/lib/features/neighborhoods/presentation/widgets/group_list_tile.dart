import 'package:flutter/material.dart';

import '../../../../core/theme/rv_spacing.dart';
import '../../../../shared/widgets/rv_card.dart';
import '../../data/models/neighborhood_group.dart';
import 'group_status_chip.dart';

class GroupListTile extends StatelessWidget {
  const GroupListTile({
    required this.group,
    super.key,
    this.isMember = false,
    this.onTap,
  });

  final NeighborhoodGroup group;
  final bool isMember;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final card = RvCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(group.name, style: theme.textTheme.titleMedium),
              ),
              GroupStatusChip(status: group.status),
            ],
          ),
          const SizedBox(height: RvSpacing.xs),
          Wrap(
            spacing: RvSpacing.sm,
            runSpacing: RvSpacing.xs,
            children: [
              Text(
                group.municipalityLabel,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (isMember)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Miembro',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
            ],
          ),
          if (group.description != null && group.description!.trim().isNotEmpty) ...[
            const SizedBox(height: RvSpacing.sm),
            Text(
              group.description!.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );

    if (onTap == null) {
      return card;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: card,
      ),
    );
  }
}
