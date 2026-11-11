import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_failure.dart';
import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/feature_shell_scaffold.dart';
import '../../../shared/widgets/rv_card.dart';
import '../../../shared/widgets/rv_primary_button.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _logoutInProgress = false;

  Future<void> _logout() async {
    if (_logoutInProgress) {
      return;
    }
    setState(() => _logoutInProgress = true);

    final remoteError = await ref.read(authControllerProvider.notifier).logout();

    if (!mounted) {
      return;
    }

    setState(() => _logoutInProgress = false);

    if (remoteError is ApiNetworkFailure || remoteError is ApiTimeoutFailure) {
      final useLocal = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Servidor no disponible'),
          content: const Text(
            'No pudimos revocar la sesión en el servidor. '
            'Puedes cerrar sesión solo en este dispositivo; el token remoto podría seguir activo hasta expirar.',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cerrar localmente')),
          ],
        ),
      );

      if (useLocal == true && mounted) {
        await ref.read(authControllerProvider.notifier).logout(localOnly: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(appConfigProvider);
    final auth = ref.watch(authControllerProvider);
    final user = auth is AuthAuthenticated ? auth.user : null;

    return FeatureShellScaffold(
      title: 'Perfil',
      phaseLabel: 'Sesión Sanctum',
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
                if (user != null) ...[
                  Text(user.name, style: Theme.of(context).textTheme.titleSmall),
                  Text(user.email),
                  const SizedBox(height: RvSpacing.md),
                  Text('Municipios', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: RvSpacing.xs),
                  if (user.municipalityMemberships.isEmpty)
                    Text(
                      'Ninguna municipalidad vinculada a tu cuenta en este perfil.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    )
                  else
                    Text(
                      user.municipalityMemberships.map((m) => m.municipality.name).join(', '),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                ] else
                  const Text('Sin datos de usuario.'),
              ],
            ),
          ),
          const SizedBox(height: RvSpacing.md),
          RvPrimaryButton(
            key: const Key('profile_logout_button'),
            label: _logoutInProgress ? 'Cerrando sesión…' : 'Cerrar sesión',
            icon: Icons.logout,
            onPressed: _logoutInProgress ? null : _logout,
          ),
        ],
      ),
    );
  }
}
