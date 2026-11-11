import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'token_storage.dart';

final tokenStorageProvider = Provider<TokenStorage>((ref) {
  if (kIsWeb) {
    return InMemoryTokenStorage();
  }
  return FlutterSecureTokenStorage(
    const FlutterSecureStorage(
      aOptions: AndroidOptions(encryptedSharedPreferences: true),
    ),
  );
});

class FlutterSecureTokenStorage implements TokenStorage {
  FlutterSecureTokenStorage(this._storage);

  static const _key = 'sanctum_bearer_token';

  final FlutterSecureStorage _storage;

  @override
  Future<String?> readToken() => _storage.read(key: _key);

  @override
  Future<void> saveToken(String token) => _storage.write(key: _key, value: token);

  @override
  Future<void> deleteToken() => _storage.delete(key: _key);
}

/// Web (desarrollo): sesión solo en memoria; se pierde al recargar la página.
class InMemoryTokenStorage implements TokenStorage {
  String? _token;

  @override
  Future<void> deleteToken() async {
    _token = null;
  }

  @override
  Future<String?> readToken() async => _token;

  @override
  Future<void> saveToken(String token) async {
    _token = token;
  }
}
