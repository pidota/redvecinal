import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/rv_empty_state.dart';
import '../../../shared/widgets/rv_primary_button.dart';
import '../application/reviewable_groups_controller.dart';
import 'widgets/group_list_tile.dart';
import 'widgets/neighborhood_api_error.dart';

class ReviewableGroupsScreen extends ConsumerWidget {
  const ReviewableGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(reviewableGroupsControllerProvider);
    final notifier = ref.read(reviewableGroupsControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Revisar solicitudes'),
        leading: BackButton(onPressed: () => context.pop()),
      ),
      body: groupsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => NeighborhoodApiError(
          title: 'No pudimos cargar las juntas',
          failure: error is ApiFailure ? error : const ApiUnexpectedFailure(),
          onRetry: () => ref.read(reviewableGroupsControllerProvider.notifier).refresh(),
        ),
        data: (page) {
          if (page.items.isEmpty) {
            return const RvEmptyState(
              title: 'Sin juntas para revisar',
              message:
                  'Cuando tengas permiso para revisar solicitudes de incorporación, '
                  'verás las juntas correspondientes aquí.',
              icon: Icons.admin_panel_settings_outlined,
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.read(reviewableGroupsControllerProvider.notifier).refresh(),
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
                        onPressed:
                            groupsAsync.isLoading || notifier.isLoadingMore ? null : () => notifier.loadMore(),
                      ),
                    ),
                  );
                }

                final group = page.items[index];
                return GroupListTile(
                  group: group,
                  onTap: () => context.push('/neighborhoods/${group.id}/review-requests'),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
