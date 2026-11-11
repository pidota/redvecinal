import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/rv_card.dart';
import '../../../shared/widgets/rv_primary_button.dart';

/// Pantalla conceptual; sin autenticación real (Fase 5.2).
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Acceso vecinal')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(RvSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Inicia sesión',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: RvSpacing.sm),
              Text(
                'El inicio de sesión con Laravel Sanctum se integrará en la Fase 5.2. '
                'Por ahora puedes explorar la navegación y el diseño de la app.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: RvSpacing.lg),
              RvCard(
                child: Column(
                  children: [
                    const TextField(
                      enabled: false,
                      decoration: InputDecoration(
                        labelText: 'Correo electrónico',
                        hintText: 'Disponible en Fase 5.2',
                      ),
                    ),
                    const SizedBox(height: RvSpacing.md),
                    const TextField(
                      enabled: false,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Contraseña',
                        hintText: 'Disponible en Fase 5.2',
                      ),
                    ),
                    const SizedBox(height: RvSpacing.lg),
                    RvPrimaryButton(
                      key: const Key('login_explore_button'),
                      label: 'Explorar la interfaz (5.1)',
                      icon: Icons.arrow_forward,
                      onPressed: () => context.go('/home'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
