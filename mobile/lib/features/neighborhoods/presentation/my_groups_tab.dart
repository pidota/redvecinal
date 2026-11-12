import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/rv_empty_state.dart';
import '../application/my_groups_controller.dart';
import 'widgets/group_list_tile.dart';
import 'widgets/neighborhood_api_error.dart';

class MyGroupsTab extends ConsumerWidget {
  const MyGroupsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(myGroupsControllerProvider);

    return groupsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => NeighborhoodApiError(
        title: 'No pudimos cargar tus juntas',
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
            itemBuilder: (context, index) {
              final group = groups[index];
              return GroupListTile(
                group: group,
                isMember: true,
                onTap: () => context.push('/neighborhoods/${group.id}'),
              );
            },
          ),
        );
      },
    );
  }
}
