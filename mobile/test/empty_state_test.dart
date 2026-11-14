import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('publicaciones muestra estado vacío explícito', (tester) async {
    await openMainShellAuthenticated(tester);

    await tester.tap(navBarIcon(Icons.article_outlined));
    await tester.pumpAndSettle();

    expect(find.text('Sin publicaciones'), findsOneWidget);
    expect(find.textContaining('Fase 5.4C'), findsWidgets);
  });
}
