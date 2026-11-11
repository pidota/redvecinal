import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/phase_notice_banner.dart';
import '../../../shared/widgets/rv_card.dart';

/// Ruta de detalle preparada; sin datos reales.
class NeighborhoodDetailScreen extends StatelessWidget {
  const NeighborhoodDetailScreen({required this.groupKey, super.key});

  final String groupKey;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de junta'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const PhaseNoticeBanner(phaseLabel: 'Fase 5.3'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(RvSpacing.md),
              children: [
                RvCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Identificador de ruta: $groupKey', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: RvSpacing.sm),
                      const Text(
                        'En fases posteriores se mostrarán miembros, publicaciones y chat de la junta.',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
