import 'package:flutter/material.dart';

import '../../../shared/widgets/feature_shell_scaffold.dart';
import 'explore_groups_tab.dart';
import 'my_groups_tab.dart';
import 'my_membership_requests_tab.dart';

class NeighborhoodsScreen extends StatelessWidget {
  const NeighborhoodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: FeatureShellScaffold(
        title: 'Juntas',
        phaseLabel: 'Fase 5.3.3C',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
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
