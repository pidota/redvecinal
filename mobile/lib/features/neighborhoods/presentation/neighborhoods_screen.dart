import 'package:flutter/material.dart';

import '../../../shared/widgets/feature_shell_scaffold.dart';
import 'explore_groups_tab.dart';
import 'my_groups_tab.dart';

class NeighborhoodsScreen extends StatelessWidget {
  const NeighborhoodsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: FeatureShellScaffold(
        title: 'Juntas',
        phaseLabel: 'Fase 5.3.2',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: const TabBar(
                tabs: [
                  Tab(text: 'Mis juntas'),
                  Tab(text: 'Explorar'),
                ],
              ),
            ),
            const Expanded(
              child: TabBarView(
                children: [
                  MyGroupsTab(),
                  ExploreGroupsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
