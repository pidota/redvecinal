/// Persistencia del Bearer Sanctum (sin contraseñas).
abstract class TokenStorage {
  Future<String?> readToken();

  Future<void> saveToken(String token);

  Future<void> deleteToken();
}
