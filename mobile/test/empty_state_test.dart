import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('publicaciones muestra estado vacío explícito', (tester) async {
    await openMainShellFromLogin(tester);

    await tester.tap(navBarIcon(Icons.article_outlined));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel(RegExp('Feed no conectado')), findsOneWidget);
    expect(find.textContaining('Fase 5.4'), findsWidgets);
  });
}
