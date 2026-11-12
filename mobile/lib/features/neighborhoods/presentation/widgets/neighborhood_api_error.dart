import 'package:flutter/material.dart';

import '../../../../core/network/api_failure.dart';
import '../../../../shared/widgets/rv_empty_state.dart';
import '../../../../shared/widgets/rv_primary_button.dart';

class NeighborhoodApiError extends StatelessWidget {
  const NeighborhoodApiError({
    required this.failure,
    required this.onRetry,
    this.title = 'No pudimos cargar la información',
    super.key,
  });

  final ApiFailure failure;
  final VoidCallback onRetry;
  final String title;

  @override
  Widget build(BuildContext context) {
    return RvEmptyState(
      title: title,
      message: failure.userMessage,
      icon: Icons.cloud_off_outlined,
      action: RvPrimaryButton(
        label: 'Reintentar',
        icon: Icons.refresh,
        onPressed: onRetry,
      ),
    );
  }
}
