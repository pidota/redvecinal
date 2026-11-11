import 'package:flutter/material.dart';

class GroupStatusChip extends StatelessWidget {
  const GroupStatusChip({required this.status, super.key});

  final String status;

  static String labelFor(String status) {
    return switch (status) {
      'active' => 'Activa',
      'inactive' => 'Inactiva',
      'suspended' => 'Suspendida',
      _ => status,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color bg, Color fg) = switch (status) {
      'active' => (scheme.primaryContainer, scheme.onPrimaryContainer),
      'suspended' => (scheme.errorContainer, scheme.onErrorContainer),
      'inactive' => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
      _ => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        labelFor(status),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg),
      ),
    );
  }
}
