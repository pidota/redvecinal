import 'package:flutter/material.dart';

import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/feature_shell_scaffold.dart';
import '../../../shared/widgets/rv_card.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FeatureShellScaffold(
      title: 'Inicio',
      phaseLabel: 'Fase 5.3+',
      body: ListView(
        padding: const EdgeInsets.all(RvSpacing.md),
        children: [
          RvCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Bienvenido a Red Vecinal', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: RvSpacing.sm),
                const Text(
                  'Aquí verás un resumen de tus juntas, novedades y accesos rápidos '
                  'cuando conectemos la API.',
                ),
              ],
            ),
          ),
          const SizedBox(height: RvSpacing.md),
          RvCard(
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: RvSpacing.md),
                const Expanded(
                  child: Text(
                    'Sin datos de backend en esta subfase: solo estructura visual y navegación.',
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
