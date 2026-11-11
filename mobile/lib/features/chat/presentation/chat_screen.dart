import 'package:flutter/material.dart';

import '../../../shared/widgets/feature_shell_scaffold.dart';
import '../../../shared/widgets/rv_empty_state.dart';

class ChatScreen extends StatelessWidget {
  const ChatScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeatureShellScaffold(
      title: 'Chat',
      phaseLabel: 'Fase 5.5',
      body: RvEmptyState(
        title: 'Salas no sincronizadas',
        message:
            'El chat grupal con Laravel Reverb y la API REST se integrará en la Fase 5.5.',
        icon: Icons.forum_outlined,
      ),
    );
  }
}
