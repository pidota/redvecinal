import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/rv_colors.dart';
import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/rv_loading_indicator.dart';
import '../application/auth_controller.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(authControllerProvider.notifier).bootstrap();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final appName = const String.fromEnvironment('APP_NAME', defaultValue: 'Red Vecinal');

    return Scaffold(
      backgroundColor: RvColors.warmBackground,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(RvSpacing.lg),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Semantics(
                header: true,
                child: Icon(
                  Icons.groups_2_outlined,
                  size: 72,
                  color: RvColors.forestGreen,
                  semanticLabel: 'Logotipo provisional Red Vecinal',
                ),
              ),
              const SizedBox(height: RvSpacing.lg),
              Text(
                appName,
                style: Theme.of(context).textTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: RvSpacing.sm),
              Text(
                'Comunidad vecinal, más cerca de tu territorio.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const Spacer(flex: 3),
              const RvLoadingIndicator(message: 'Iniciando…'),
              const SizedBox(height: RvSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
