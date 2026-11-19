import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/theme/rv_spacing.dart';
import '../../../posts/application/post_moderation_discovery_controller.dart';
import '../../data/models/neighborhood_group.dart';

/// Entrada opcional hacia la cola de moderación desde el detalle de junta.
class PostModerationDetailEntry extends ConsumerWidget {
  const PostModerationDetailEntry({required this.group, super.key});

  final NeighborhoodGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = PostModerationDiscoveryKey(
      groupId: group.id,
      groupStatus: group.status,
    );
    final discoveryAsync = ref.watch(
      postModerationDiscoveryControllerProvider(key),
    );

    return discoveryAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (state) {
        if (state.visibility != PostModerationDiscoveryVisibility.visible) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final query =
            group.name.trim().isNotEmpty
                ? '?groupName=${Uri.encodeComponent(group.name.trim())}'
                : '';

        return Padding(
          padding: const EdgeInsets.only(top: RvSpacing.md),
          child: Material(
            color: theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            child: Semantics(
              button: true,
              label: 'Moderar publicaciones',
              child: ListTile(
                leading: const Icon(Icons.fact_check_outlined),
                title: const Text('Moderar publicaciones'),
                subtitle: const Text(
                  'Revisar publicaciones pendientes de aprobación',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap:
                    () => context.push(
                      '/neighborhoods/${group.id}/posts/pending$query',
                    ),
              ),
            ),
          ),
        );
      },
    );
  }
}
