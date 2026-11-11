import 'package:flutter/material.dart';

import 'phase_notice_banner.dart';

/// Scaffold común para pantallas de pestaña principal.
class FeatureShellScaffold extends StatelessWidget {
  const FeatureShellScaffold({
    required this.title,
    required this.phaseLabel,
    required this.body,
    super.key,
    this.floatingActionButton,
  });

  final String title;
  final String phaseLabel;
  final Widget body;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      floatingActionButton: floatingActionButton,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PhaseNoticeBanner(phaseLabel: phaseLabel),
          Expanded(child: body),
        ],
      ),
    );
  }
}
