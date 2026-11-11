import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  testWidgets('navegación inferior cambia entre las cinco secciones', (tester) async {
    await openMainShellAuthenticated(tester);

    expect(find.text('Inicio'), findsWidgets);
    expect(find.text('Bienvenido a Red Vecinal'), findsOneWidget);

    await tester.tap(navBarIcon(Icons.holiday_village_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Sin juntas cargadas'), findsOneWidget);

    await tester.tap(navBarIcon(Icons.article_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Feed no conectado'), findsOneWidget);

    await tester.tap(navBarIcon(Icons.forum_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Salas no sincronizadas'), findsOneWidget);

    await tester.tap(navBarIcon(Icons.person_outline));
    await tester.pumpAndSettle();
    expect(find.text('Sesión'), findsOneWidget);
  });
}
