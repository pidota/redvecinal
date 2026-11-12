import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/rv_empty_state.dart';
import '../../../shared/widgets/rv_primary_button.dart';
import '../application/explore_groups_controller.dart';
import '../application/my_groups_controller.dart';
import '../data/models/neighborhood_group.dart';
import 'widgets/group_list_tile.dart';
import 'widgets/neighborhood_api_error.dart';

class ExploreGroupsTab extends ConsumerWidget {
  const ExploreGroupsTab({super.key});

  Set<int> _memberIds(AsyncValue<List<NeighborhoodGroup>> myGroups) {
    return myGroups.maybeWhen(
      data: (list) => list.map((g) => g.id).toSet(),
      orElse: () => <int>{},
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exploreAsync = ref.watch(exploreGroupsControllerProvider);
    final myGroupsAsync = ref.watch(myGroupsControllerProvider);
    final memberIds = _memberIds(myGroupsAsync);

    return exploreAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => NeighborhoodApiError(
        title: 'No pudimos cargar el listado',
        failure: error is ApiFailure ? error : const ApiUnexpectedFailure(),
        onRetry: () => ref.read(exploreGroupsControllerProvider.notifier).refresh(),
      ),
      data: (page) {
        if (page.items.isEmpty) {
          return const RvEmptyState(
            title: 'Sin juntas disponibles',
            message:
                'No hay juntas visibles en tus municipalidades. '
                'El municipio publicará nuevas juntas cuando corresponda.',
            icon: Icons.search_off_outlined,
          );
        }

        return RefreshIndicator(
          onRefresh: () => ref.read(exploreGroupsControllerProvider.notifier).refresh(),
          child: ListView.builder(
            padding: const EdgeInsets.all(RvSpacing.md),
            itemCount: page.items.length + (page.hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index >= page.items.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: RvSpacing.md),
                  child: Center(
                    child: RvPrimaryButton(
                      label: 'Cargar más',
                      icon: Icons.expand_more,
                      onPressed: exploreAsync.isLoading ||
                              ref.read(exploreGroupsControllerProvider.notifier).isLoadingMore
                          ? null
                          : () => ref.read(exploreGroupsControllerProvider.notifier).loadMore(),
                    ),
                  ),
                );
              }

              final group = page.items[index];
              return Padding(
                padding: const EdgeInsets.only(bottom: RvSpacing.sm),
                child: GroupListTile(
                  group: group,
                  isMember: memberIds.contains(group.id),
                  onTap: () => context.push('/neighborhoods/${group.id}'),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
