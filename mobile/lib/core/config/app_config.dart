import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Configuración por entorno vía `--dart-define` (sin secretos en código).
class AppConfig {
  const AppConfig({
    required this.appName,
    required this.environment,
    required this.apiBaseUrl,
    this.connectTimeout = const Duration(seconds: 15),
    this.receiveTimeout = const Duration(seconds: 30),
  });

  final String appName;
  final String environment;
  final String apiBaseUrl;
  final Duration connectTimeout;
  final Duration receiveTimeout;

  bool get isDevelopment => environment == 'development';

  bool get isProduction => environment == 'production';

  bool get hasApiBaseUrl => apiBaseUrl.trim().isNotEmpty;

  static AppConfig fromEnvironment() {
    const env = String.fromEnvironment('APP_ENV', defaultValue: 'development');
    const name = String.fromEnvironment('APP_NAME', defaultValue: 'Red Vecinal');
    const apiBase = String.fromEnvironment('API_BASE_URL', defaultValue: '');

    return AppConfig(
      appName: name,
      environment: env,
      apiBaseUrl: apiBase,
    );
  }
}

final appConfigProvider = Provider<AppConfig>((ref) {
  throw UnimplementedError('appConfigProvider debe sobreescribirse en main()');
});
