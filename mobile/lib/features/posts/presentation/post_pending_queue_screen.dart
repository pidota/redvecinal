import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/rv_empty_state.dart';
import '../../../shared/widgets/rv_loading_indicator.dart';
import '../../../shared/widgets/rv_primary_button.dart';
import '../../neighborhoods/presentation/widgets/neighborhood_api_error.dart';
import '../application/post_pending_queue_controller.dart';
import '../data/models/paginated_pending_queue.dart';
import 'widgets/post_pending_queue_card.dart';

class PostPendingQueueScreen extends ConsumerWidget {
  const PostPendingQueueScreen({
    required this.groupId,
    this.groupName,
    super.key,
  });

  final int groupId;
  final String? groupName;

  String get _title {
    final name = groupName?.trim();
    if (name != null && name.isNotEmpty) {
      return 'Pendientes · $name';
    }
    return 'Publicaciones pendientes';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(postPendingQueueControllerProvider(groupId));
    final notifier = ref.read(
      postPendingQueueControllerProvider(groupId).notifier,
    );

    return Scaffold(
      appBar: AppBar(title: Text(_title), leading: const BackButton()),
      body: queueAsync.when(
        loading: () => const Center(child: RvLoadingIndicator()),
        error:
            (error, _) => _QueueErrorView(
              error: error,
              onRetry: _canRetry(error) ? () => notifier.refresh() : null,
            ),
        data:
            (queue) => _QueueBody(
              groupId: groupId,
              groupName: groupName,
              queue: queue,
              queueAsync: queueAsync,
              notifier: notifier,
            ),
      ),
    );
  }

  bool _canRetry(Object error) {
    if (error is ApiForbiddenFailure || error is ApiSessionExpiredFailure) {
      return false;
    }
    return true;
  }
}

class _QueueErrorView extends StatelessWidget {
  const _QueueErrorView({required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    if (error is ApiForbiddenFailure) {
      return RvEmptyState(
        title: 'Acceso denegado',
        message: (error as ApiForbiddenFailure).userMessage,
        icon: Icons.lock_outline,
        action: TextButton(
          onPressed: () => Navigator.maybePop(context),
          child: const Text('Volver'),
        ),
      );
    }

    if (error is ApiNotFoundFailure) {
      return RvEmptyState(
        title: 'Junta no disponible',
        message: (error as ApiNotFoundFailure).userMessage,
        icon: Icons.search_off_outlined,
        action: TextButton(
          onPressed: () => Navigator.maybePop(context),
          child: const Text('Volver'),
        ),
      );
    }

    if (error is ApiSessionExpiredFailure) {
      return RvEmptyState(
        title: 'Sesión finalizada',
        message: (error as ApiSessionExpiredFailure).userMessage,
        icon: Icons.lock_clock_outlined,
        action: TextButton(
          onPressed: () => Navigator.maybePop(context),
          child: const Text('Volver'),
        ),
      );
    }

    return NeighborhoodApiError(
      title: 'No pudimos cargar la cola',
      failure:
          error is ApiFailure
              ? error as ApiFailure
              : const ApiUnexpectedFailure(),
      onRetry: onRetry ?? () {},
    );
  }
}

class _QueueBody extends StatelessWidget {
  const _QueueBody({
    required this.groupId,
    required this.queue,
    required this.queueAsync,
    required this.notifier,
    this.groupName,
  });

  final int groupId;
  final String? groupName;
  final PaginatedPendingQueue queue;
  final AsyncValue<PaginatedPendingQueue> queueAsync;
  final PostPendingQueueController notifier;

  @override
  Widget build(BuildContext context) {
    final items = queue.reviewableItems;

    if (queue.hasOnlySkippedItems) {
      return RefreshIndicator(
        onRefresh: notifier.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(RvSpacing.md),
          children: [
            _SkippedBanner(count: queue.skippedItemCount),
            const SizedBox(height: RvSpacing.md),
            RvEmptyState(
              title: 'Sin entradas revisables',
              message:
                  'Hay publicaciones en la cola del servidor, pero ninguna '
                  'incluye el contenido pendiente necesario para moderarlas aquí.',
              icon: Icons.fact_check_outlined,
              action: RvPrimaryButton(
                label: 'Actualizar',
                icon: Icons.refresh,
                onPressed: notifier.refresh,
              ),
            ),
          ],
        ),
      );
    }

    if (queue.isTrulyEmpty) {
      return RefreshIndicator(
        onRefresh: notifier.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(RvSpacing.md),
          children: [
            RvEmptyState(
              title: 'Sin publicaciones pendientes',
              message:
                  'Cuando los vecinos envíen propuestas o enmiendas a revisión, '
                  'aparecerán aquí.',
              icon: Icons.fact_check_outlined,
              action: RvPrimaryButton(
                label: 'Actualizar',
                icon: Icons.refresh,
                onPressed: notifier.refresh,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(RvSpacing.md),
        itemCount: _itemCount(queue, items.length),
        itemBuilder: (context, index) {
          var cardIndex = index;
          if (queue.skippedItemCount > 0) {
            if (index == 0) {
              return Padding(
                padding: const EdgeInsets.only(bottom: RvSpacing.sm),
                child: _SkippedBanner(count: queue.skippedItemCount),
              );
            }
            cardIndex = index - 1;
          }

          if (cardIndex >= items.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: RvSpacing.md),
              child: Center(
                child: RvPrimaryButton(
                  label: 'Cargar más',
                  icon: Icons.expand_more,
                  onPressed:
                      queueAsync.isLoading || notifier.isLoadingMore
                          ? null
                          : notifier.loadMore,
                ),
              ),
            );
          }

          final review = items[cardIndex];
          final query =
              groupName != null && groupName!.trim().isNotEmpty
                  ? '?groupName=${Uri.encodeComponent(groupName!.trim())}'
                  : '';
          return Padding(
            padding: const EdgeInsets.only(bottom: RvSpacing.sm),
            child: PostPendingQueueCard(
              review: review,
              onTap:
                  () => context.push(
                    '/neighborhoods/$groupId/posts/pending/${review.post.id}$query',
                  ),
            ),
          );
        },
      ),
    );
  }

  int _itemCount(PaginatedPendingQueue queue, int reviewableCount) {
    var count = reviewableCount;
    if (queue.skippedItemCount > 0) {
      count += 1;
    }
    if (queue.hasMore) {
      count += 1;
    }
    return count;
  }
}

class _SkippedBanner extends StatelessWidget {
  const _SkippedBanner({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(RvSpacing.sm),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.info_outline,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: RvSpacing.sm),
            Expanded(
              child: Text(
                '$count publicación(es) de la cola no se muestran porque '
                'el servidor no incluyó el contenido pendiente. '
                'No son lo mismo que una cola vacía.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
