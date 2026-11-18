import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/rv_spacing.dart';
import '../../application/create_post_local_attachment.dart';
import '../../application/edit_post_attachment_upload_support.dart';
import '../../application/edit_post_attachments_controller.dart';
import '../../application/edit_post_attachments_persistence.dart';
import '../../application/edit_post_controller.dart';
import '../../support/post_attachment_limits.dart';
import '../../data/models/post_detail.dart';

class EditPostAttachmentSection extends ConsumerWidget {
  const EditPostAttachmentSection({
    required this.postId,
    required this.busy,
    super.key,
  });

  final int postId;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(editPostAttachmentsControllerProvider(postId));
    final session = ref.watch(editPostControllerProvider(postId)).valueOrNull;
    final notifier = ref.read(
      editPostAttachmentsControllerProvider(postId).notifier,
    );
    final persistence = ref.watch(editPostAttachmentsPersistenceProvider);
    final record = persistence.recordForPost(postId);
    final uncertain = record?.uncertainUploads ?? const [];
    final patchBlocks =
        session?.patchUncertain == true || session?.saveInFlight == true;
    final theme = Theme.of(context);
    final remaining = state.remainingSlots(uncertain);
    final canAdd = state.canAddMore(
      patchBlocks: patchBlocks,
      uncertainRecords: uncertain,
    );

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
        ),
        if (state.hasBlockingUncertain ||
            (record?.hasUnresolvedUncertain ?? false)) ...[
          const SizedBox(height: RvSpacing.sm),
          Text(
            editPostUncertainUploadBlockedMessage,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
          const SizedBox(height: RvSpacing.xs),
          OutlinedButton(
            onPressed:
                busy || state.reconcileInFlight
                    ? null
                    : () => notifier.reconcileUploadsFromServer(),
            child: const Text('Verificar subidas en servidor'),
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
        if (patchBlocks) ...[
          const SizedBox(height: RvSpacing.sm),
          Text(
            'Hay un guardado de texto incierto o en curso. Resuélvelo antes de subir archivos.',
            style: theme.textTheme.bodySmall,
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
            if (state.needsUpload.isNotEmpty)
              FilledButton.icon(
                onPressed:
                    busy || state.uploadInFlight || patchBlocks
                        ? null
                        : () => notifier.uploadPending(),
                icon: const Icon(Icons.cloud_upload_outlined),
                label: const Text('Subir seleccionados'),
              ),
          ],
        ),
        if (state.serverAttachments.isNotEmpty) ...[
          const SizedBox(height: RvSpacing.md),
          Text('En el servidor', style: theme.textTheme.labelLarge),
          for (final attachment in state.serverAttachments)
            _ServerAttachmentRow(attachment: attachment),
        ],
        if (state.localItems.isNotEmpty) ...[
          const SizedBox(height: RvSpacing.md),
          Text(
            'Pendientes en el dispositivo',
            style: theme.textTheme.labelLarge,
          ),
          for (final item in state.localItems)
            _LocalAttachmentRow(
              item: item,
              busy: busy,
              onRemove:
                  item.canRemoveLocally
                      ? () => notifier.removeLocalSelected(item.clientId)
                      : null,
            ),
        ],
      ],
    );
  }
}

class _ServerAttachmentRow extends StatelessWidget {
  const _ServerAttachmentRow({required this.attachment});

  final PostAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: RvSpacing.sm),
      child: ListTile(
        leading: Icon(_iconFor(attachment.mimeType)),
        title: Text(
          attachment.sanitizedFileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '${attachment.formattedSize()} · ${attachment.mimeType}',
        ),
        trailing: Text('Solo lectura', style: theme.textTheme.labelSmall),
      ),
    );
  }
}

class _LocalAttachmentRow extends StatelessWidget {
  const _LocalAttachmentRow({
    required this.item,
    required this.busy,
    this.onRemove,
  });

  final CreatePostLocalAttachment item;
  final bool busy;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
            Text('${_formatSize(item.sizeBytes)} · ${_statusLabel(item)}'),
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
            onRemove != null && !busy
                ? IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close),
                  tooltip: 'Quitar selección local',
                )
                : null,
      ),
    );
  }
}

IconData _iconFor(String mime) {
  if (mime.startsWith('image/')) {
    return Icons.image_outlined;
  }
  if (mime == 'application/pdf') {
    return Icons.picture_as_pdf_outlined;
  }
  return Icons.attach_file;
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

String _statusLabel(CreatePostLocalAttachment item) {
  switch (item.state) {
    case CreatePostAttachmentState.selected:
      return 'Seleccionado';
    case CreatePostAttachmentState.uploading:
      return 'Subiendo…';
    case CreatePostAttachmentState.uploaded:
      return 'Subido';
    case CreatePostAttachmentState.failed:
      return 'Error';
    case CreatePostAttachmentState.uncertain:
      return 'Incertidumbre';
  }
}
