import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Configuración mínima por entorno (sin secretos ni URLs definitivas).
class AppConfig {
  const AppConfig({
    required this.appName,
    required this.environment,
  });

  final String appName;
  final String environment;

  bool get isDevelopment => environment == 'development';

  bool get isProduction => environment == 'production';

  static AppConfig fromEnvironment() {
    const env = String.fromEnvironment('APP_ENV', defaultValue: 'development');
    const name = String.fromEnvironment('APP_NAME', defaultValue: 'Red Vecinal');

    return AppConfig(appName: name, environment: env);
  }
}

final appConfigProvider = Provider<AppConfig>((ref) {
  throw UnimplementedError('appConfigProvider debe sobreescribirse en main()');
});
