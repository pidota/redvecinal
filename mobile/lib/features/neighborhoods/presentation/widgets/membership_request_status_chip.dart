import 'package:flutter/material.dart';

import '../../data/models/membership_request.dart';

class MembershipRequestStatusChip extends StatelessWidget {
  const MembershipRequestStatusChip({required this.status, super.key});

  final String status;

  Color _color(ThemeData theme) {
    return switch (status) {
      'pending' => theme.colorScheme.tertiary,
      'approved' => theme.colorScheme.primary,
      'rejected' => theme.colorScheme.error,
      'cancelled' => theme.colorScheme.outline,
      _ => theme.colorScheme.surfaceContainerHighest,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
  final label = membershipRequestStatusLabel(status);

    return Chip(
      label: Text(label),
      visualDensity: VisualDensity.compact,
      backgroundColor: _color(theme).withValues(alpha: 0.12),
      side: BorderSide(color: _color(theme).withValues(alpha: 0.4)),
    );
  }
}
