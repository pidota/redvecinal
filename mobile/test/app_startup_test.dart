import 'package:flutter_test/flutter_test.dart';

import 'test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('la aplicación muestra splash e inicia flujo hacia login', (tester) async {
    await pumpRedVecinalApp(tester);

    expect(find.text('Red Vecinal'), findsOneWidget);
    expect(find.text('Iniciando…'), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pumpAndSettle();

    expect(find.text('Acceso vecinal'), findsOneWidget);
    expect(find.text('Explorar la interfaz (5.1)'), findsOneWidget);
  });
}
