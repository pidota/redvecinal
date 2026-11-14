import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/rv_spacing.dart';
import '../../../neighborhoods/application/neighborhood_session.dart';
import '../../application/post_detail_controller.dart';
import '../../data/models/post_detail.dart';

class PostReactionControl extends ConsumerStatefulWidget {
  const PostReactionControl({
    required this.postId,
    required this.detail,
    super.key,
  });

  final int postId;
  final PostDetail detail;

  @override
  ConsumerState<PostReactionControl> createState() =>
      _PostReactionControlState();
}

class _PostReactionControlState extends ConsumerState<PostReactionControl> {
  bool _localProcessing = false;

  @override
  Widget build(BuildContext context) {
    final sessionValid = neighborhoodSessionEpoch(ref) != null;
    if (!widget.detail.isPublished || !sessionValid) {
      return _ReactionCountOnly(count: widget.detail.engagement.reactionsCount);
    }

    final notifier = ref.read(
      postDetailControllerProvider(widget.postId).notifier,
    );
    final processing = _localProcessing || notifier.isReactionInFlight;
    final hasLike = widget.detail.engagement.hasLike;
    final theme = Theme.of(context);
    final label = hasLike ? 'Quitar me gusta' : 'Me gusta';

    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: processing ? null : _toggle,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            vertical: RvSpacing.xs,
            horizontal: RvSpacing.xs,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (processing)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: theme.colorScheme.primary,
                  ),
                )
              else
                Icon(
                  hasLike ? Icons.favorite : Icons.favorite_border,
                  size: 22,
                  color:
                      hasLike
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                ),
              const SizedBox(width: RvSpacing.xs),
              Text(
                '${widget.detail.engagement.reactionsCount} reacciones',
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggle() async {
    final epochBefore = neighborhoodSessionEpoch(ref);
    setState(() => _localProcessing = true);
    final notifier = ref.read(
      postDetailControllerProvider(widget.postId).notifier,
    );
    final failure = await notifier.toggleLikeReaction();
    if (!mounted) {
      return;
    }
    setState(() => _localProcessing = false);
    if (neighborhoodSessionEpoch(ref) != epochBefore) {
      return;
    }
    if (failure != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(failure.userMessage)));
    }
  }
}

class _ReactionCountOnly extends StatelessWidget {
  const _ReactionCountOnly({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.favorite_border,
          size: 22,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: RvSpacing.xs),
        Text('$count reacciones', style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
