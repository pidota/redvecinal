import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef UnauthorizedHandler = Future<void> Function();

/// Registrado desde [AuthController.bootstrap] para evitar dependencias circulares con Dio.
final unauthorizedHandlerProvider = StateProvider<UnauthorizedHandler?>((ref) => null);
