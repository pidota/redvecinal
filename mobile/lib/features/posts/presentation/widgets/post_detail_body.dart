import 'package:flutter/material.dart';

import '../../../../core/theme/rv_spacing.dart';

/// Muestra el cuerpo en texto plano (sin HTML ni WebView).
class PostDetailBody extends StatelessWidget {
  const PostDetailBody({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paragraphs =
        text.isEmpty ? <String>[] : text.split(RegExp(r'\n{2,}'));

    if (paragraphs.isEmpty) {
      return Text('Sin contenido', style: theme.textTheme.bodyMedium);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < paragraphs.length; i++) ...[
          if (i > 0) const SizedBox(height: RvSpacing.sm),
          SelectableText(
            paragraphs[i].replaceAll(RegExp(r'\n'), ' ').trim(),
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ],
    );
  }
}
