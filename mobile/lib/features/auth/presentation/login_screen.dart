import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/rv_card.dart';
import '../../../shared/widgets/rv_primary_button.dart';
import '../application/auth_controller.dart';
import '../domain/auth_state.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_errorMessage != null) {
      setState(() => _errorMessage = null);
    }

    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }

    final auth = ref.read(authControllerProvider);
    if (auth is AuthAuthenticating) {
      return;
    }

    final failure = await ref.read(authControllerProvider.notifier).login(
          email: _emailController.text,
          password: _passwordController.text,
        );

    if (!mounted) {
      return;
    }

    if (failure != null) {
      setState(() => _errorMessage = _messageForFailure(failure));
    }
  }

  String _messageForFailure(ApiFailure failure) {
    if (failure is ApiValidationFailure) {
      final first = failure.fieldErrors.values.expand((e) => e).firstOrNull;
      return first ?? failure.userMessage;
    }
  if (failure is ApiRateLimitedFailure && failure.retryAfter != null) {
      final minutes = failure.retryAfter!.inMinutes.clamp(1, 60);
      return '${failure.userMessage} ($minutes min aprox.)';
    }
    return failure.userMessage;
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final isSubmitting = auth is AuthAuthenticating;

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
                'Ingresa con tu cuenta vecinal autorizada por tu municipalidad.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: RvSpacing.lg),
              if (_errorMessage != null) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    _errorMessage!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                  ),
                ),
                const SizedBox(height: RvSpacing.md),
              ],
              RvCard(
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        key: const Key('login_email_field'),
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username, AutofillHints.email],
                        decoration: const InputDecoration(
                          labelText: 'Correo electrónico',
                        ),
                        validator: (value) {
                          final trimmed = value?.trim() ?? '';
                          if (trimmed.isEmpty) {
                            return 'Ingresa tu correo.';
                          }
                          if (!trimmed.contains('@')) {
                            return 'Correo no válido.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: RvSpacing.md),
                      TextFormField(
                        key: const Key('login_password_field'),
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        onFieldSubmitted: (_) => isSubmitting ? null : _submit(),
                        decoration: InputDecoration(
                          labelText: 'Contraseña',
                          suffixIcon: IconButton(
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            icon: Icon(_obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                            tooltip: _obscurePassword ? 'Mostrar contraseña' : 'Ocultar contraseña',
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Ingresa tu contraseña.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: RvSpacing.lg),
                      RvPrimaryButton(
                        key: const Key('login_submit_button'),
                        label: isSubmitting ? 'Ingresando…' : 'Iniciar sesión',
                        icon: Icons.login,
                        onPressed: isSubmitting ? null : _submit,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
