import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/rv_primary_button.dart';
import '../application/auth_controller.dart';
import '../domain/auth_state.dart';

class SessionRetryScreen extends ConsumerWidget {
  const SessionRetryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    final message = auth is AuthRecoverableError
        ? auth.message
        : 'No pudimos verificar tu sesión.';

    return Scaffold(
      appBar: AppBar(title: const Text('Conexión')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RvSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Problema de conexión',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: RvSpacing.sm),
              Text(message),
              const Spacer(),
              RvPrimaryButton(
                label: 'Reintentar',
                icon: Icons.refresh,
                onPressed: () {
                  ref.read(authControllerProvider.notifier).retryRestoreSession();
                },
              ),
              const SizedBox(height: RvSpacing.md),
              TextButton(
                onPressed: () async {
                  await ref.read(authControllerProvider.notifier).logout(localOnly: true);
                },
                child: const Text('Cerrar sesión localmente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
