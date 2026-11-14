import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/rv_card.dart';
import '../../../shared/widgets/rv_empty_state.dart';
import '../../../shared/widgets/rv_loading_indicator.dart';
import '../../neighborhoods/presentation/widgets/neighborhood_api_error.dart';
import '../application/post_detail_controller.dart';
import '../data/models/post_detail.dart';
import 'widgets/post_attachment_list.dart';
import 'widgets/post_detail_body.dart';

class PostDetailScreen extends ConsumerWidget {
  const PostDetailScreen({required this.postId, super.key});

  final int postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(postDetailControllerProvider(postId));
    final notifier = ref.read(postDetailControllerProvider(postId).notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Publicación'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: detailAsync.when(
        loading: () => const Center(child: RvLoadingIndicator()),
        error:
            (error, _) => _DetailErrorView(
              error: error,
              onRetry: notifier.refresh,
              onBack: () => context.pop(),
            ),
        data:
            (detail) => RefreshIndicator(
              onRefresh: notifier.refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(RvSpacing.md),
                children: [_PostDetailContent(detail: detail, postId: postId)],
              ),
            ),
      ),
    );
  }
}

class _DetailErrorView extends StatelessWidget {
  const _DetailErrorView({
    required this.error,
    required this.onRetry,
    required this.onBack,
  });

  final Object error;
  final VoidCallback onRetry;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    if (error is ApiNotFoundFailure) {
      return RvEmptyState(
        title: 'Publicación no disponible',
        message:
            'No encontramos esta publicación o ya no tienes acceso. '
            'Puede haber sido retirada o moderada.',
        icon: Icons.article_outlined,
        action: TextButton(onPressed: onBack, child: const Text('Volver')),
      );
    }

    if (error is ApiSessionExpiredFailure) {
      return RvEmptyState(
        title: 'Sesión finalizada',
        message: (error as ApiSessionExpiredFailure).userMessage,
        icon: Icons.lock_clock_outlined,
        action: TextButton(onPressed: onBack, child: const Text('Volver')),
      );
    }

    return NeighborhoodApiError(
      title: 'No pudimos cargar la publicación',
      failure:
          error is ApiFailure
              ? error as ApiFailure
              : const ApiUnexpectedFailure(),
      onRetry: onRetry,
    );
  }
}

class _PostDetailContent extends ConsumerWidget {
  const _PostDetailContent({required this.detail, required this.postId});

  final PostDetail detail;
  final int postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final categoryName = detail.category?.name ?? 'Publicación';
    final notifier = ref.read(postDetailControllerProvider(postId).notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RvCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(detail.title, style: theme.textTheme.headlineSmall),
              const SizedBox(height: RvSpacing.sm),
              Text(detail.author.name, style: theme.textTheme.labelLarge),
              const SizedBox(height: RvSpacing.xs),
              Wrap(
                spacing: RvSpacing.xs,
                runSpacing: RvSpacing.xs,
                children: [
                  _MetaChip(
                    icon:
                        detail.isMunicipal
                            ? Icons.account_balance_outlined
                            : Icons.groups_outlined,
                    text: detail.scopeLabel,
                  ),
                  _MetaChip(icon: Icons.category_outlined, text: categoryName),
                ],
              ),
              const SizedBox(height: RvSpacing.sm),
              Text(
                _formatPostDate(context, detail.publishedAt),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: RvSpacing.md),
              PostDetailBody(text: detail.bodyDisplay),
              const SizedBox(height: RvSpacing.md),
              Row(
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: RvSpacing.xs),
                  Text('${detail.engagement.commentsCount} comentarios'),
                  const SizedBox(width: RvSpacing.md),
                  Icon(
                    Icons.favorite_border,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: RvSpacing.xs),
                  Text('${detail.engagement.reactionsCount} reacciones'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: RvSpacing.md),
        PostAttachmentList(
          attachments: detail.attachments,
          onDownload: (attachment) async {
            final result = await notifier.downloadAttachment(attachment);
            if (result.sessionEnded) {
              return const PostAttachmentDownloadFeedback(
                message: 'La descarga se canceló porque la sesión cambió.',
                isError: true,
              );
            }
            if (result.failed || result.savedPath == null) {
              return const PostAttachmentDownloadFeedback(
                message: 'No pudimos guardar el archivo.',
                isError: true,
              );
            }
            return const PostAttachmentDownloadFeedback(
              message:
                  'Archivo guardado temporalmente en la aplicación. '
                  'La opción para abrirlo estará disponible próximamente.',
            );
          },
        ),
      ],
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

String _formatPostDate(BuildContext context, DateTime? value) {
  if (value == null) {
    return 'Fecha no disponible';
  }
  final local = value.toLocal();
  final date =
      '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
  final time =
      '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  return '$date · $time';
}
