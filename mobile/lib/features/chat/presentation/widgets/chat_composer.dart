import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/rv_colors.dart';
import '../../../../core/theme/rv_spacing.dart';
import '../../data/chat_repository.dart';

class ChatComposer extends StatelessWidget {
  const ChatComposer({
    required this.controller,
    required this.enabled,
    required this.canSend,
    required this.sending,
    required this.onSend,
    super.key,
    this.readOnlyReason,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool canSend;
  final bool sending;
  final VoidCallback onSend;
  final String? readOnlyReason;

  @override
  Widget build(BuildContext context) {
    if (readOnlyReason != null) {
      return Material(
        color: RvColors.amber.withValues(alpha: 0.18),
        child: Padding(
          padding: const EdgeInsets.all(RvSpacing.md),
          child: Text(
            readOnlyReason!,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      );
    }

    final length = controller.text.length;
    final nearLimit = length >= ChatRepository.maxBodyLength - 400;

    return Material(
      color: RvColors.surfaceWhite,
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          RvSpacing.md,
          RvSpacing.sm,
          RvSpacing.md,
          RvSpacing.md,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (nearLimit)
              Padding(
                padding: const EdgeInsets.only(bottom: RvSpacing.xs),
                child: Text(
                  '$length / ${ChatRepository.maxBodyLength}',
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: length >= ChatRepository.maxBodyLength
                            ? RvColors.error
                            : RvColors.textMuted,
                      ),
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    enabled: enabled && !sending,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: ChatRepository.maxBodyLength,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    textInputAction: TextInputAction.newline,
                    decoration: const InputDecoration(
                      hintText: 'Escribe un mensaje',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: RvSpacing.sm),
                IconButton.filled(
                  onPressed: canSend && !sending ? onSend : null,
                  icon: sending
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send),
                  tooltip: 'Enviar mensaje',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
