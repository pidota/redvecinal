import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/rv_empty_state.dart';

class NeighborhoodDetailInvalidRouteScreen extends StatelessWidget {
  const NeighborhoodDetailInvalidRouteScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de junta'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: RvEmptyState(
        title: 'Ruta no válida',
        message: 'El identificador de junta no es válido.',
        icon: Icons.error_outline,
        action: TextButton(onPressed: () => context.pop(), child: const Text('Volver')),
      ),
    );
  }
}
