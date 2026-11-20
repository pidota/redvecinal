import 'package:flutter/material.dart';

import '../../../../core/theme/rv_colors.dart';
import '../../../../core/theme/rv_spacing.dart';
import '../../application/chat_outgoing.dart';
import '../../data/models/chat_enums.dart';
import '../../data/models/chat_message.dart';
import '../chat_labels.dart';

class ChatMessageBubble extends StatelessWidget {
  const ChatMessageBubble({
    required this.isMine,
    super.key,
    this.message,
    this.outgoing,
    this.onRetry,
  });

  final ChatMessage? message;
  final ChatOutgoingMessage? outgoing;
  final bool isMine;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final outgoingStatus = outgoing?.status;
    final server = message ?? outgoing?.confirmed;
    final body = _bodyText(server, outgoing);
    final timestamp = formatChatTimestamp(server?.createdAt);
    final alignment = isMine ? Alignment.centerRight : Alignment.centerLeft;
    final background = isMine ? RvColors.forestGreen : RvColors.surfaceWhite;
    final foreground = isMine ? RvColors.surfaceWhite : RvColors.textDark;

    return Align(
      alignment: alignment,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: Semantics(
          container: true,
          label: _semanticsLabel(body, outgoingStatus, timestamp),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _borderColor(outgoingStatus)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: RvSpacing.md,
                vertical: RvSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment:
                    isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  if (!isMine)
                    Text(
                      'Vecino ${server?.senderId ?? ''}',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: RvColors.textMuted,
                          ),
                    ),
                  Text(
                    body,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: foreground,
                        ),
                  ),
                  if (timestamp.isNotEmpty) ...[
                    const SizedBox(height: RvSpacing.xs),
                    Text(
                      timestamp,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: isMine
                                ? RvColors.surfaceWhite.withValues(alpha: 0.85)
                                : RvColors.textMuted,
                          ),
                    ),
                  ],
                  if (_statusChip(server, outgoingStatus) != null) ...[
                    const SizedBox(height: RvSpacing.xs),
                    Text(
                      _statusChip(server, outgoingStatus)!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: isMine ? RvColors.amber : RvColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                  if (outgoingStatus == ChatOutgoingStatus.sending)
                    const Padding(
                      padding: EdgeInsets.only(top: RvSpacing.xs),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  if (onRetry != null) ...[
                    const SizedBox(height: RvSpacing.xs),
                    TextButton(
                      onPressed: onRetry,
                      child: const Text('Reintentar envío'),
                    ),
                  ],
                  if (outgoing?.failure != null &&
                      outgoingStatus == ChatOutgoingStatus.failedBeforeDispatch)
                    Text(
                      outgoing!.failure!.userMessage,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: isMine ? RvColors.amber : RvColors.error,
                          ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _bodyText(ChatMessage? server, ChatOutgoingMessage? pending) {
    if (server?.status == ChatMessageStatus.deletedBySender) {
      return 'Este mensaje fue eliminado';
    }
    if (server?.status == ChatMessageStatus.hidden) {
      return server?.body ?? '';
    }
    if (pending != null && pending.status != ChatOutgoingStatus.confirmed) {
      return pending.body;
    }
    return server?.body ?? pending?.body ?? '';
  }

  String? _statusChip(ChatMessage? server, ChatOutgoingStatus? outgoingStatus) {
    if (outgoingStatus != null &&
        outgoingStatus != ChatOutgoingStatus.confirmed &&
        outgoingStatus != ChatOutgoingStatus.draft) {
      return chatOutgoingStatusLabel(outgoingStatus);
    }
    if (server?.status == ChatMessageStatus.hidden) {
      return 'Oculto';
    }
    if (server?.status == ChatMessageStatus.deletedBySender) {
      return 'Eliminado';
    }
    return null;
  }

  Color _borderColor(ChatOutgoingStatus? status) {
    switch (status) {
      case ChatOutgoingStatus.uncertain:
        return RvColors.amber;
      case ChatOutgoingStatus.failedBeforeDispatch:
        return RvColors.error;
      default:
        return Colors.transparent;
    }
  }

  String _semanticsLabel(
    String body,
    ChatOutgoingStatus? status,
    String timestamp,
  ) {
    final parts = <String>[
      isMine ? 'Mensaje propio' : 'Mensaje de otro vecino',
      body,
    ];
    if (timestamp.isNotEmpty) {
      parts.add(timestamp);
    }
    if (status != null) {
      parts.add(chatOutgoingStatusLabel(status));
    }
    return parts.join('. ');
  }
}
