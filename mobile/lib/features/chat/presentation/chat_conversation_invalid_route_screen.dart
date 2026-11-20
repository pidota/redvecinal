import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/rv_empty_state.dart';

class ChatConversationInvalidRouteScreen extends StatelessWidget {
  const ChatConversationInvalidRouteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Conversación'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: RvEmptyState(
        title: 'Ruta no válida',
        message: 'El identificador de sala no es válido.',
        icon: Icons.error_outline,
        action: TextButton(
          onPressed: () => context.pop(),
          child: const Text('Volver'),
        ),
      ),
    );
  }
}
