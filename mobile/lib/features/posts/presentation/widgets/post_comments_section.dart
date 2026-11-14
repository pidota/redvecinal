import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_failure.dart';
import '../../../../core/theme/rv_spacing.dart';
import '../../../../shared/widgets/rv_card.dart';
import '../../../../shared/widgets/rv_empty_state.dart';
import '../../../../shared/widgets/rv_loading_indicator.dart';
import '../../../../shared/widgets/rv_primary_button.dart';
import '../../../neighborhoods/application/neighborhood_session.dart';
import '../../../neighborhoods/presentation/widgets/neighborhood_api_error.dart';
import '../../application/post_comments_controller.dart';
import '../../data/models/post_comment.dart';
import '../../data/models/post_detail.dart';

class PostCommentsSection extends ConsumerWidget {
  const PostCommentsSection({
    required this.postId,
    required this.detail,
    super.key,
  });

  final int postId;
  final PostDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commentsAsync = ref.watch(postCommentsControllerProvider(postId));
    final notifier = ref.read(postCommentsControllerProvider(postId).notifier);
    final sessionValid = neighborhoodSessionEpoch(ref) != null;
    final showComposer =
        sessionValid && detail.isPublished && detail.commentsEnabled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Comentarios', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: RvSpacing.sm),
        commentsAsync.when(
          loading:
              () => const Padding(
                padding: EdgeInsets.symmetric(vertical: RvSpacing.lg),
                child: Center(child: RvLoadingIndicator()),
              ),
          error: (error, _) {
            if (error is ApiNotFoundFailure) {
              return const RvEmptyState(
                title: 'Comentarios no disponibles',
                message:
                    'No pudimos cargar los comentarios de esta publicación.',
                icon: Icons.chat_bubble_outline,
              );
            }
            return NeighborhoodApiError(
              title: 'No pudimos cargar los comentarios',
              failure:
                  error is ApiFailure ? error : const ApiUnexpectedFailure(),
              onRetry: notifier.refresh,
            );
          },
          data: (page) {
            final isLoadingMore = notifier.isLoadingMore;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (page.items.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: RvSpacing.md),
                    child: RvEmptyState(
                      title: 'Sin comentarios aún',
                      message: 'Sé el primero en dejar un comentario.',
                      icon: Icons.chat_bubble_outline,
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: page.items.length,
                    separatorBuilder:
                        (_, __) => const SizedBox(height: RvSpacing.sm),
                    itemBuilder: (context, index) {
                      return PostCommentTile(comment: page.items[index]);
                    },
                  ),
                if (page.hasMore) ...[
                  const SizedBox(height: RvSpacing.sm),
                  Center(
                    child: TextButton(
                      onPressed:
                          isLoadingMore ? null : () => notifier.loadMore(),
                      child:
                          isLoadingMore
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : const Text('Cargar más comentarios'),
                    ),
                  ),
                ],
                if (!detail.commentsEnabled) ...[
                  const SizedBox(height: RvSpacing.sm),
                  Text(
                    'Los comentarios nuevos están deshabilitados en esta publicación.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (showComposer) ...[
                  const SizedBox(height: RvSpacing.md),
                  PostCommentComposer(postId: postId),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class PostCommentTile extends StatelessWidget {
  const PostCommentTile({required this.comment, super.key});

  final PostComment comment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return RvCard(
      child: Semantics(
        label: 'Comentario de ${comment.authorDisplayName}',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(comment.authorDisplayName, style: theme.textTheme.labelLarge),
            const SizedBox(height: RvSpacing.xs),
            Text(
              _formatCommentDate(context, comment.createdAt),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: RvSpacing.sm),
            SelectableText(
              comment.plainBody,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

class PostCommentComposer extends ConsumerStatefulWidget {
  const PostCommentComposer({required this.postId, super.key});

  final int postId;

  @override
  ConsumerState<PostCommentComposer> createState() =>
      _PostCommentComposerState();
}

class _PostCommentComposerState extends ConsumerState<PostCommentComposer> {
  final _controller = TextEditingController();
  bool _submitting = false;
  String? _fieldError;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }

    final epochBefore = neighborhoodSessionEpoch(ref);
    if (epochBefore == null) {
      return;
    }

    final text = _controller.text;
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      setState(() => _fieldError = 'Escribe un comentario antes de enviar.');
      return;
    }
    if (trimmed.length > 5000) {
      setState(
        () => _fieldError = 'El comentario no puede superar 5000 caracteres.',
      );
      return;
    }

    setState(() {
      _fieldError = null;
      _submitting = true;
    });

    final failure = await ref
        .read(postCommentsControllerProvider(widget.postId).notifier)
        .submitComment(text);

    if (!mounted) {
      return;
    }

    if (neighborhoodSessionEpoch(ref) != epochBefore) {
      setState(() => _submitting = false);
      return;
    }

    setState(() => _submitting = false);

    if (failure != null) {
      final message =
          failure is ApiValidationFailure
              ? failure.userMessage
              : failure.userMessage;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    _controller.clear();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Comentario publicado.')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notifier = ref.read(
      postCommentsControllerProvider(widget.postId).notifier,
    );
    final blocked = _submitting || notifier.isSubmitting;

    return RvCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Escribir comentario', style: theme.textTheme.titleSmall),
          const SizedBox(height: RvSpacing.sm),
          TextField(
            controller: _controller,
            minLines: 2,
            maxLines: 5,
            maxLength: 5000,
            enabled: !blocked,
            textInputAction: TextInputAction.newline,
            decoration: InputDecoration(
              hintText: 'Comparte tu opinión…',
              errorText: _fieldError,
              border: const OutlineInputBorder(),
              counterText: '',
            ),
            onChanged: (_) {
              if (_fieldError != null) {
                setState(() => _fieldError = null);
              }
            },
          ),
          const SizedBox(height: RvSpacing.sm),
          RvPrimaryButton(
            label: blocked ? 'Enviando…' : 'Publicar comentario',
            onPressed: blocked ? null : _submit,
          ),
        ],
      ),
    );
  }
}

String _formatCommentDate(BuildContext context, DateTime? value) {
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
