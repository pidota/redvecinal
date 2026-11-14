import 'package:flutter/material.dart';

import '../../../../core/theme/rv_spacing.dart';
import '../../../../shared/widgets/rv_card.dart';
import '../../data/models/feed_post.dart';
import '../../data/models/feed_post_mine_presentation.dart';

class MyPostListCard extends StatelessWidget {
  const MyPostListCard({required this.post, required this.onOpen, super.key});

  final FeedPost post;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = FeedPostMinePresentation.listTitle(post);
    final excerpt = FeedPostMinePresentation.listExcerpt(post);
    final statusLabel = FeedPostMinePresentation.statusLabel(post.status);
    final categoryName = post.category?.name;
    final showAmendment = FeedPostMinePresentation.showsAmendmentHint(post);

    return RvCard(
      onTap: onOpen,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: RvSpacing.sm),
              _StatusChip(label: statusLabel),
            ],
          ),
          if (showAmendment) ...[
            const SizedBox(height: RvSpacing.xs),
            Text(
              'Enmienda en revisión',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
          const SizedBox(height: RvSpacing.xs),
          Wrap(
            spacing: RvSpacing.xs,
            runSpacing: RvSpacing.xs,
            children: [
              _MetaChip(
                icon:
                    post.isMunicipal
                        ? Icons.account_balance_outlined
                        : Icons.groups_outlined,
                text: post.scopeLabel,
              ),
              if (categoryName != null && categoryName.isNotEmpty)
                _MetaChip(icon: Icons.category_outlined, text: categoryName),
            ],
          ),
          if (post.publishedAt != null) ...[
            const SizedBox(height: RvSpacing.sm),
            Text(
              _formatPublishedAt(context, post.publishedAt),
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (excerpt.isNotEmpty) ...[
            const SizedBox(height: RvSpacing.sm),
            Text(
              excerpt,
              style: theme.textTheme.bodyMedium,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  String _formatPublishedAt(BuildContext context, DateTime? value) {
    if (value == null) {
      return '';
    }
    final local = value.toLocal();
    final date =
        '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    return 'Publicada · $date · $time';
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RvSpacing.sm,
        vertical: RvSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RvSpacing.sm,
        vertical: RvSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: RvSpacing.xs),
          Flexible(
            child: Text(
              text,
              style: theme.textTheme.labelMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
