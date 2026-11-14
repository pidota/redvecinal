import 'package:flutter/material.dart';

import '../../../../core/theme/rv_spacing.dart';
import '../../../../shared/widgets/rv_card.dart';
import '../../data/models/feed_post.dart';

class PostFeedCard extends StatelessWidget {
  const PostFeedCard({required this.post, super.key});

  final FeedPost post;

  String _formatPublishedAt(BuildContext context, DateTime? value) {
    if (value == null) {
      return 'Fecha no disponible';
    }
    final local = value.toLocal();
    final now = DateTime.now();
    final isToday =
        local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;

    final time =
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    if (isToday) {
      return 'Hoy · $time';
    }
    final date =
        '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
    return '$date · $time';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final categoryName = post.category?.name ?? 'Publicación';
    final excerpt = post.excerpt;

    return Semantics(
      container: true,
      label:
          'Publicación: ${post.title}. Autor ${post.author.name}. $categoryName. ${post.scopeLabel}.',
      child: RvCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              post.title,
              style: theme.textTheme.titleMedium,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: RvSpacing.xs),
            Text(post.author.name, style: theme.textTheme.labelLarge),
            const SizedBox(height: RvSpacing.xs),
            Wrap(
              spacing: RvSpacing.xs,
              runSpacing: RvSpacing.xs,
              children: [
                _ChipLabel(
                  icon:
                      post.isMunicipal
                          ? Icons.account_balance_outlined
                          : Icons.groups_outlined,
                  text: post.scopeLabel,
                ),
                _ChipLabel(icon: Icons.category_outlined, text: categoryName),
              ],
            ),
            const SizedBox(height: RvSpacing.sm),
            Text(
              _formatPublishedAt(context, post.publishedAt),
              style: theme.textTheme.bodySmall,
            ),
            if (excerpt.isNotEmpty) ...[
              const SizedBox(height: RvSpacing.sm),
              Text(
                excerpt,
                style: theme.textTheme.bodyMedium,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: RvSpacing.sm),
            Row(
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: RvSpacing.xs),
                Text('${post.engagement.commentsCount}'),
                const SizedBox(width: RvSpacing.md),
                Icon(
                  Icons.favorite_border,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: RvSpacing.xs),
                Text('${post.engagement.reactionsCount}'),
                if (post.attachments.isNotEmpty) ...[
                  const Spacer(),
                  Icon(
                    Icons.attach_file,
                    size: 18,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: RvSpacing.xs),
                  Text(
                    '${post.attachments.length}',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ChipLabel extends StatelessWidget {
  const _ChipLabel({required this.icon, required this.text});

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
