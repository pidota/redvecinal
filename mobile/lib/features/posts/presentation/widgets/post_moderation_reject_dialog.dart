import 'package:flutter/material.dart';

import '../../../../core/network/api_failure.dart';
import '../../../../core/theme/rv_spacing.dart';
import '../../data/post_moderation_failure.dart';

/// Resultado del formulario de rechazo (motivo o cancelación).
class PostModerationRejectDialogResult {
  const PostModerationRejectDialogResult._(this.reason);

  const PostModerationRejectDialogResult.cancelled() : this._(null);

  const PostModerationRejectDialogResult.confirmed(String reason)
    : this._(reason);

  final String? reason;

  bool get isConfirmed => reason != null;
}

Future<PostModerationRejectDialogResult?> showPostModerationRejectDialog({
  required BuildContext context,
  required bool isAmendment,
  String? initialValidationMessage,
  String? initialReason,
}) {
  return showDialog<PostModerationRejectDialogResult>(
    context: context,
    builder:
        (context) => _PostModerationRejectDialog(
          isAmendment: isAmendment,
          initialValidationMessage: initialValidationMessage,
          initialReason: initialReason,
        ),
  );
}

class _PostModerationRejectDialog extends StatefulWidget {
  const _PostModerationRejectDialog({
    required this.isAmendment,
    this.initialValidationMessage,
    this.initialReason,
  });

  final bool isAmendment;
  final String? initialValidationMessage;
  final String? initialReason;

  @override
  State<_PostModerationRejectDialog> createState() =>
      _PostModerationRejectDialogState();
}

class _PostModerationRejectDialogState
    extends State<_PostModerationRejectDialog> {
  final _controller = TextEditingController();
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _errorText = widget.initialValidationMessage;
    final seed = widget.initialReason;
    if (seed != null && seed.isNotEmpty) {
      _controller.text = seed;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _validateAndConfirm() {
    final reason = _controller.text;
    final failure = validatePostRejectionReason(reason);
    if (failure != null) {
      setState(() => _errorText = failure.userMessage);
      return;
    }
    Navigator.pop(context, PostModerationRejectDialogResult.confirmed(reason));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final advisory =
        widget.isAmendment
            ? 'La modificación será rechazada, pero la versión actualmente '
                'publicada permanecerá sin cambios.'
            : 'La publicación será rechazada y no quedará visible para los '
                'vecinos autorizados.';

    return AlertDialog(
      title: const Text('Rechazar publicación'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(advisory, style: theme.textTheme.bodyMedium),
            const SizedBox(height: RvSpacing.md),
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                labelText: 'Motivo del rechazo',
                errorText: _errorText,
                counterText:
                    '${_controller.text.length}/$postModerationRejectionReasonMaxLength',
              ),
              maxLines: 4,
              maxLength: postModerationRejectionReasonMaxLength,
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() => _errorText = null);
                }
                setState(() {});
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed:
              () => Navigator.pop(
                context,
                const PostModerationRejectDialogResult.cancelled(),
              ),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _validateAndConfirm,
          child: const Text('Confirmar rechazo'),
        ),
      ],
    );
  }
}

/// Muestra errores de validación del servidor en el mismo diálogo.
Future<void> showRejectServerValidationSnackBar(
  BuildContext context,
  ApiFailure failure,
) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(failure.userMessage),
      backgroundColor: Theme.of(context).colorScheme.error,
    ),
  );
  return Future.value();
}
