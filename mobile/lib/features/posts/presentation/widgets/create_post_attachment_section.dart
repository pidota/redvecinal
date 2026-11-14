import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/rv_spacing.dart';
import '../../application/create_post_local_attachment.dart';
import '../../application/create_post_attachments_controller.dart';
import '../../application/create_post_session_persistence.dart';
import '../../support/post_attachment_limits.dart';

class CreatePostAttachmentSection extends ConsumerWidget {
  const CreatePostAttachmentSection({required this.busy, super.key});

  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(createPostAttachmentsProvider);
    final session = ref.watch(createPostSessionPersistenceProvider);
    final notifier = ref.read(createPostAttachmentsProvider.notifier);
    final theme = Theme.of(context);
    final remaining = state.remainingSlots(session);
    final canAdd = state.canAddMore(session);
    final blockingUncertain = state.hasBlockingUncertain(session);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Archivos adjuntos', style: theme.textTheme.titleSmall),
        const SizedBox(height: RvSpacing.xs),
        Text(
          'Hasta ${PostAttachmentLimits.maxPerRevision} archivos · máx. 5 MB c/u · JPG, PNG, WebP o PDF',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: RvSpacing.sm),
        Text(
          'Disponibles: ${remaining.clamp(0, PostAttachmentLimits.maxPerRevision)}',
          style: theme.textTheme.labelLarge,
          semanticsLabel:
              'Espacios disponibles para adjuntos: $remaining de ${PostAttachmentLimits.maxPerRevision}',
        ),
        if (session.hasUnresolvedUncertainUpload) ...[
          const SizedBox(height: RvSpacing.sm),
          Text(
            uncertainUploadBlockedMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ] else if (blockingUncertain) ...[
          const SizedBox(height: RvSpacing.sm),
          Text(
            'Hay una o más subidas sin confirmación HTTP 201. El envío a moderación '
            'permanece bloqueado.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        if (state.bannerMessage != null) ...[
          const SizedBox(height: RvSpacing.sm),
          Text(
            state.bannerMessage!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: RvSpacing.sm),
        Wrap(
          spacing: RvSpacing.sm,
          runSpacing: RvSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed:
                  busy || !canAdd
                      ? null
                      : () async {
                        await notifier.pickAndAddImage();
                      },
              icon: const Icon(Icons.image_outlined),
              label: const Text('Imagen'),
            ),
            OutlinedButton.icon(
              onPressed:
                  busy || !canAdd
                      ? null
                      : () async {
                        await notifier.pickAndAddPdf();
                      },
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('PDF'),
            ),
          ],
        ),
        if (state.items.isNotEmpty) ...[
          const SizedBox(height: RvSpacing.md),
          for (final item in state.items)
            _AttachmentRow(item: item, busy: busy),
        ],
      ],
    );
  }
}

class _AttachmentRow extends ConsumerWidget {
  const _AttachmentRow({required this.item, required this.busy});

  final CreatePostLocalAttachment item;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(createPostAttachmentsProvider.notifier);
    final theme = Theme.of(context);
    final subtitle = _statusLabel(item);

    return Card(
      margin: const EdgeInsets.only(bottom: RvSpacing.sm),
      child: ListTile(
        leading: Icon(_iconFor(item.mimeType)),
        title: Text(
          item.displayName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${_formatSize(item.sizeBytes)} · $subtitle'),
            if (item.userMessage != null)
              Text(
                item.userMessage!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            if (item.state == CreatePostAttachmentState.uploading &&
                item.uploadProgress != null)
              Padding(
                padding: const EdgeInsets.only(top: RvSpacing.xs),
                child: LinearProgressIndicator(value: item.uploadProgress),
              ),
          ],
        ),
        trailing:
            item.canRemoveLocally && !busy
                ? IconButton(
                  onPressed: () => notifier.removeLocal(item.clientId),
                  icon: const Icon(Icons.close),
                  tooltip: 'Quitar',
                )
                : item.state == CreatePostAttachmentState.failed && !busy
                ? IconButton(
                  onPressed: () => notifier.markRetryAllowed(item.clientId),
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Preparar reintento',
                )
                : null,
      ),
    );
  }

  static IconData _iconFor(String mime) {
    if (mime.startsWith('image/')) {
      return Icons.image_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  static String _statusLabel(CreatePostLocalAttachment item) {
    return switch (item.state) {
      CreatePostAttachmentState.selected => 'Listo para subir',
      CreatePostAttachmentState.uploading => 'Subiendo…',
      CreatePostAttachmentState.uploaded => 'En el servidor',
      CreatePostAttachmentState.failed => 'Error',
      CreatePostAttachmentState.uncertain => 'Resultado incierto',
    };
  }
}

String _formatSize(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}
