import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/rv_card.dart';
import '../../../shared/widgets/rv_empty_state.dart';
import '../application/group_detail_controller.dart';
import 'widgets/group_status_chip.dart';
import 'widgets/neighborhood_api_error.dart';

class NeighborhoodDetailScreen extends ConsumerWidget {
  const NeighborhoodDetailScreen({required this.groupId, super.key});

  final int groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(groupDetailControllerProvider(groupId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de junta'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: detailAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) {
          if (error is ApiForbiddenFailure) {
            return RvEmptyState(
              title: 'Acceso denegado',
              message: error.userMessage,
              icon: Icons.lock_outline,
              action: TextButton(onPressed: () => context.pop(), child: const Text('Volver')),
            );
          }
          if (error is ApiNotFoundFailure) {
            return RvEmptyState(
              title: 'Junta no encontrada',
              message: error.userMessage,
              icon: Icons.search_off_outlined,
              action: TextButton(onPressed: () => context.pop(), child: const Text('Volver')),
            );
          }
          return NeighborhoodApiError(
            title: 'No pudimos cargar el detalle',
            failure: error is ApiFailure ? error : const ApiUnexpectedFailure(),
            onRetry: () => ref.read(groupDetailControllerProvider(groupId).notifier).refresh(),
          );
        },
        data: (group) {
          return ListView(
            padding: const EdgeInsets.all(RvSpacing.md),
            children: [
              RvCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(group.name, style: theme.textTheme.headlineSmall),
                        ),
                        GroupStatusChip(status: group.status),
                      ],
                    ),
                    const SizedBox(height: RvSpacing.sm),
                    Text(
                      group.municipalityLabel,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (group.address != null && group.address!.trim().isNotEmpty) ...[
                      const SizedBox(height: RvSpacing.md),
                      Text('Dirección', style: theme.textTheme.labelLarge),
                      const SizedBox(height: RvSpacing.xs),
                      Text(group.address!.trim()),
                    ],
                    if (group.description != null && group.description!.trim().isNotEmpty) ...[
                      const SizedBox(height: RvSpacing.md),
                      Text('Descripción', style: theme.textTheme.labelLarge),
                      const SizedBox(height: RvSpacing.xs),
                      Text(group.description!.trim()),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
