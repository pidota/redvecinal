import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/feature_shell_scaffold.dart';
import '../../../shared/widgets/rv_empty_state.dart';
import '../../../shared/widgets/rv_primary_button.dart';

class NeighborhoodsScreen extends StatelessWidget {
  const NeighborhoodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FeatureShellScaffold(
      title: 'Juntas',
      phaseLabel: 'Fase 5.3',
      body: RvEmptyState(
        title: 'Sin juntas cargadas',
        message:
            'El listado de juntas y membresías se obtendrá de /api/v1/me/groups en la Fase 5.3.',
        icon: Icons.holiday_village_outlined,
        action: RvPrimaryButton(
          label: 'Ver detalle de ejemplo',
          onPressed: () => context.push('/neighborhoods/ejemplo'),
        ),
      ),
    );
  }
}
