import 'package:flutter/material.dart';

import '../application/edit_post_patch_support.dart';

/// Vista previa truncada para diálogos (no altera el payload ni el formulario).
String editPostDialogPreview(String text, {int maxChars = 160}) {
  final trimmed = text.trim();
  if (trimmed.length <= maxChars) {
    return trimmed;
  }
  return '${trimmed.substring(0, maxChars)}… (${trimmed.length} caracteres en total)';
}

Future<bool?> showEditPostAdoptOfferDialog({
  required BuildContext context,
  required String intro,
  required bool conflict,
  required EditPostPatchPayload pending,
  required String remoteTitle,
  required String remoteBody,
}) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final maxHeight = MediaQuery.sizeOf(ctx).height * 0.55;
      return AlertDialog(
        title: Text(
          conflict
              ? 'Versión distinta en el servidor'
              : 'Coincidencia en el servidor',
        ),
        content: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(intro),
                const SizedBox(height: 12),
                if (conflict) ...[
                  Text(
                    'Tu intento local',
                    style: Theme.of(ctx).textTheme.labelLarge,
                  ),
                  Text('Título: ${editPostDialogPreview(pending.title)}'),
                  Text('Contenido: ${editPostDialogPreview(pending.body)}'),
                  const SizedBox(height: 8),
                  Text('Servidor', style: Theme.of(ctx).textTheme.labelLarge),
                  Text('Título: ${editPostDialogPreview(remoteTitle)}'),
                  Text('Contenido: ${editPostDialogPreview(remoteBody)}'),
                  const SizedBox(height: 8),
                  const Text(
                    'Si continúas con el servidor, los cambios locales no '
                    'confirmados podrían descartarse. No implica que tu PATCH '
                    'anterior haya sido confirmado por HTTP.',
                  ),
                ] else
                  const Text(
                    'Puedes continuar editando a partir del estado observado '
                    'del servidor. Esto no demuestra que la respuesta del PATCH '
                    'anterior haya sido exitosa.',
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Conservar incertidumbre'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Usar estado del servidor'),
          ),
        ],
      );
    },
  );
}
