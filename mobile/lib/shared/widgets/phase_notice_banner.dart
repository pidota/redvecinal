import 'package:flutter/material.dart';

import '../../core/theme/rv_colors.dart';
import '../../core/theme/rv_spacing.dart';

/// Aviso visible de que la sección se conectará al backend en subfases futuras.
class PhaseNoticeBanner extends StatelessWidget {
  const PhaseNoticeBanner({
    required this.phaseLabel,
    super.key,
  });

  final String phaseLabel;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Aviso de desarrollo: $phaseLabel',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: RvSpacing.md,
          vertical: RvSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: RvColors.amber.withValues(alpha: 0.25),
          border: Border(
            bottom: BorderSide(color: RvColors.amber.withValues(alpha: 0.5)),
          ),
        ),
        child: Text(
          'Interfaz preliminar — integración con Laravel en $phaseLabel.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: RvColors.textDark,
                fontWeight: FontWeight.w500,
              ),
        ),
      ),
    );
  }
}
