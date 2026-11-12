import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../shared/widgets/feature_shell_scaffold.dart';
import '../application/reviewable_groups_controller.dart';
import 'explore_groups_tab.dart';
import 'my_groups_tab.dart';
import 'my_membership_requests_tab.dart';

class NeighborhoodsScreen extends ConsumerWidget {
  const NeighborhoodsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reviewableAsync = ref.watch(reviewableGroupsControllerProvider);

    return DefaultTabController(
      length: 3,
      child: FeatureShellScaffold(
        title: 'Juntas',
        phaseLabel: 'Fase 5.3.3D-C',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            reviewableAsync.when(
              loading: () => const LinearProgressIndicator(minHeight: 2),
              error: (_, __) => const SizedBox.shrink(),
              data: (page) {
                if (page.items.isEmpty) {
                  return const SizedBox.shrink();
                }
                return Material(
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: ListTile(
                    leading: const Icon(Icons.admin_panel_settings_outlined),
                    title: const Text('Revisar solicitudes'),
                    subtitle: const Text('Gestión de incorporaciones pendientes'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push('/neighborhoods/review'),
                  ),
                );
              },
            ),
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: const TabBar(
                isScrollable: true,
                tabs: [
                  Tab(text: 'Mis juntas'),
                  Tab(text: 'Explorar'),
                  Tab(text: 'Mis solicitudes'),
                ],
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  MyGroupsTab(),
                  ExploreGroupsTab(),
                  MyMembershipRequestsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
