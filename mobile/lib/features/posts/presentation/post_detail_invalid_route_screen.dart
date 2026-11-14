import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/rv_empty_state.dart';

class PostDetailInvalidRouteScreen extends StatelessWidget {
  const PostDetailInvalidRouteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Publicación'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: RvEmptyState(
        title: 'Publicación no disponible',
        message:
            'El enlace no es válido. Revisa la publicación e inténtalo de nuevo.',
        icon: Icons.link_off_outlined,
        action: TextButton(
          onPressed: () => context.pop(),
          child: const Text('Volver'),
        ),
      ),
    );
  }
}
