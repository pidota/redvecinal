import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/feature_shell_scaffold.dart';
import '../../../shared/widgets/rv_card.dart';
import '../../../shared/widgets/rv_primary_button.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(appConfigProvider);

    return FeatureShellScaffold(
      title: 'Perfil',
      phaseLabel: 'Fase 5.2',
      body: ListView(
        padding: const EdgeInsets.all(RvSpacing.md),
        children: [
          RvCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Sesión', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: RvSpacing.sm),
                Text('Entorno: ${config.environment}'),
                const SizedBox(height: RvSpacing.xs),
                const Text('No hay usuario autenticado en esta subfase.'),
              ],
            ),
          ),
          const SizedBox(height: RvSpacing.md),
          RvPrimaryButton(
            label: 'Volver al acceso conceptual',
            onPressed: () => context.go('/login'),
          ),
        ],
      ),
    );
  }
}
