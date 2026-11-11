import 'package:flutter/material.dart';

import '../../../shared/widgets/feature_shell_scaffold.dart';
import '../../../shared/widgets/rv_empty_state.dart';

class PostsScreen extends StatelessWidget {
  const PostsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeatureShellScaffold(
      title: 'Publicaciones',
      phaseLabel: 'Fase 5.4',
      body: RvEmptyState(
        title: 'Feed no conectado',
        message:
            'Las publicaciones comunitarias y municipales se cargarán desde /api/v1/posts en la Fase 5.4.',
        icon: Icons.article_outlined,
      ),
    );
  }
}
