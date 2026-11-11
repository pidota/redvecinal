import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('en pantalla estrecha el contenido permanece accesible', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

    await openMainShellAuthenticated(tester);

    await tester.tap(navBarIcon(Icons.article_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Feed no conectado'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
