import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/feature_shell_scaffold.dart';
import '../../../shared/widgets/rv_card.dart';
import '../../../shared/widgets/rv_empty_state.dart';
import '../../../shared/widgets/rv_primary_button.dart';
import '../application/my_groups_controller.dart';
import '../data/models/neighborhood_group.dart';
import 'widgets/group_status_chip.dart';

class NeighborhoodsScreen extends ConsumerWidget {
  const NeighborhoodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(myGroupsControllerProvider);

    return FeatureShellScaffold(
      title: 'Mis juntas',
      phaseLabel: 'Fase 5.3.1',
      body: groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _ErrorState(
          failure: error is ApiFailure ? error : const ApiUnexpectedFailure(),
          onRetry: () => ref.read(myGroupsControllerProvider.notifier).refresh(),
        ),
        data: (groups) {
          if (groups.isEmpty) {
            return const RvEmptyState(
              title: 'Sin juntas',
              message:
                  'Aún no apareces en ninguna junta con membresía activa. '
                  'Cuando un operador municipal te incorpore, la verás aquí.',
              icon: Icons.holiday_village_outlined,
            );
          }
          return RefreshIndicator(
            onRefresh: () => ref.read(myGroupsControllerProvider.notifier).refresh(),
            child: ListView.separated(
              padding: const EdgeInsets.all(RvSpacing.md),
              itemCount: groups.length,
              separatorBuilder: (_, __) => const SizedBox(height: RvSpacing.sm),
              itemBuilder: (context, index) => _GroupCard(group: groups[index]),
            ),
          );
        },
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final NeighborhoodGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RvCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(group.name, style: theme.textTheme.titleMedium),
              ),
              GroupStatusChip(status: group.status),
            ],
          ),
          const SizedBox(height: RvSpacing.xs),
          Text(
            group.municipalityLabel,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (group.description != null && group.description!.trim().isNotEmpty) ...[
            const SizedBox(height: RvSpacing.sm),
            Text(
              group.description!.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.failure,
    required this.onRetry,
  });

  final ApiFailure failure;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return RvEmptyState(
      title: 'No pudimos cargar tus juntas',
      message: failure.userMessage,
      icon: Icons.cloud_off_outlined,
      action: RvPrimaryButton(
        label: 'Reintentar',
        icon: Icons.refresh,
        onPressed: onRetry,
      ),
    );
  }
}
