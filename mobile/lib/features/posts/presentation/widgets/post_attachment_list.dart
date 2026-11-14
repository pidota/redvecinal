import 'package:flutter/material.dart';

import '../../../../core/network/api_failure.dart';
import '../../../../core/theme/rv_spacing.dart';
import '../../data/models/post_detail.dart';

typedef PostAttachmentDownloadCallback =
    Future<PostAttachmentDownloadFeedback> Function(PostAttachment attachment);

class PostAttachmentDownloadFeedback {
  const PostAttachmentDownloadFeedback({
    required this.message,
    this.isError = false,
  });

  final String message;
  final bool isError;
}

class PostAttachmentList extends StatelessWidget {
  const PostAttachmentList({
    required this.attachments,
    required this.onDownload,
    super.key,
  });

  final List<PostAttachment> attachments;
  final PostAttachmentDownloadCallback onDownload;

  @override
  Widget build(BuildContext context) {
    if (attachments.isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Archivos adjuntos', style: theme.textTheme.titleSmall),
        const SizedBox(height: RvSpacing.sm),
        for (final attachment in attachments)
          _AttachmentTile(attachment: attachment, onDownload: onDownload),
      ],
    );
  }
}

class _AttachmentTile extends StatefulWidget {
  const _AttachmentTile({required this.attachment, required this.onDownload});

  final PostAttachment attachment;
  final PostAttachmentDownloadCallback onDownload;

  @override
  State<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<_AttachmentTile> {
  bool _downloading = false;

  Future<void> _handleDownload() async {
    if (_downloading) {
      return;
    }
    setState(() => _downloading = true);
    try {
      final feedback = await widget.onDownload(widget.attachment);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(feedback.message),
          backgroundColor:
              feedback.isError ? Theme.of(context).colorScheme.error : null,
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      final message =
          error is ApiFailure
              ? error.userMessage
              : 'No pudimos guardar el archivo temporalmente.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;

    return Semantics(
      button: true,
      label:
          'Guardar temporalmente ${attachment.originalDisplayName}, ${attachment.formattedSize()}',
      child: Card(
        margin: const EdgeInsets.only(bottom: RvSpacing.sm),
        child: ListTile(
          leading: const Icon(Icons.attach_file),
          title: Text(attachment.originalDisplayName),
          subtitle: Text(
            '${attachment.mimeType} · ${attachment.formattedSize()}',
          ),
          trailing:
              _downloading
                  ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : IconButton(
                    icon: const Icon(Icons.save_alt_outlined),
                    tooltip: 'Guardar temporalmente',
                    onPressed: _handleDownload,
                  ),
          onTap: _downloading ? null : _handleDownload,
        ),
      ),
    );
  }
}
