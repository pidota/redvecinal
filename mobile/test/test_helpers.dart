import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/app.dart';
import 'package:red_vecinal/core/config/app_config.dart';

Future<void> pumpRedVecinalApp(WidgetTester tester) async {
  const config = AppConfig(appName: 'Red Vecinal', environment: 'development');

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(config),
      ],
      child: const RedVecinalApp(),
    ),
  );
}

Future<void> openMainShellFromLogin(WidgetTester tester) async {
  await pumpRedVecinalApp(tester);
  await tester.pump(const Duration(milliseconds: 1300));
  await tester.pumpAndSettle();
  final exploreButton = find.byKey(const Key('login_explore_button'));
  await tester.ensureVisible(exploreButton);
  await tester.tap(exploreButton);
  await tester.pumpAndSettle();
}

Finder navBarIcon(IconData icon) {
  return find.descendant(
    of: find.byType(NavigationBar),
    matching: find.byIcon(icon),
  );
}
