import 'package:flutter/material.dart';

import '../../../../core/theme/rv_spacing.dart';
import '../../../../shared/widgets/rv_card.dart';
import '../../data/models/feed_post.dart';
import '../../data/models/post_moderation_review.dart';

class PostPendingQueueCard extends StatelessWidget {
  const PostPendingQueueCard({required this.review, this.onTap, super.key});

  final PostModerationReview review;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final post = review.post;
    final kindLabel =
        review.isAmendment ? 'Modificación pendiente' : 'Nueva publicación';
    final excerpt = FeedPost.excerptFromBody(
      review.pendingBody,
      maxLength: 140,
    );

    return RvCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            kindLabel,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: RvSpacing.xs),
          Text(
            review.pendingTitle,
            style: theme.textTheme.titleMedium,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: RvSpacing.sm),
          Text(post.author.name, style: theme.textTheme.labelLarge),
          const SizedBox(height: RvSpacing.xs),
          if (post.category != null)
            Text(
              post.category!.name,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
          if (review.pendingAttachments.isNotEmpty) ...[
            const SizedBox(height: RvSpacing.sm),
            Text(
              '${review.pendingAttachments.length} adjunto(s) en revisión',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}
