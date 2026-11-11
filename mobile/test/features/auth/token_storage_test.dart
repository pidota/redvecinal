import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';

void main() {
  test('almacenamiento en memoria guarda y elimina token', () async {
    final storage = InMemoryTokenStorage();

    expect(await storage.readToken(), isNull);
    await storage.saveToken('1|abc');
    expect(await storage.readToken(), '1|abc');
    await storage.deleteToken();
    expect(await storage.readToken(), isNull);
  });
}
