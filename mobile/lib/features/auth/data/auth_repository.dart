import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_failure.dart';
import 'models/auth_user.dart';
import 'models/login_response.dart';
import 'device_name.dart';

abstract class AuthGateway {
  Future<LoginResponse> login({required String email, required String password});

  Future<AuthUser> me();

  Future<void> logout();
}

final authRepositoryProvider = Provider<AuthGateway>((ref) {
  return AuthRepository(
    ref.watch(dioProvider),
    ref.watch(appConfigProvider),
  );
});

class AuthRepository implements AuthGateway {
  AuthRepository(this._dio, this._config);

  final Dio _dio;
  final AppConfig _config;

  @override
  Future<LoginResponse> login({
    required String email,
    required String password,
  }) async {
    _ensureConfigured();
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/login',
        data: {
          'email': email.trim(),
          'password': password,
          'device_name': defaultDeviceName(),
        },
      );

      final data = response.data;
      if (response.statusCode != 200 || data == null) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
        );
      }

      return LoginResponse.fromJson(data);
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: true);
    }
  }

  @override
  Future<AuthUser> me() async {
    _ensureConfigured();
    try {
      final response = await _dio.get<Map<String, dynamic>>('/me');

      final data = response.data;
      if (response.statusCode != 200 || data == null) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
        );
      }

      return AuthUser.fromJson(data);
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  @override
  Future<void> logout() async {
    _ensureConfigured();
    try {
      final response = await _dio.post<void>('/auth/logout');
      if (response.statusCode != 204 && response.statusCode != 200) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
        );
      }
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  void _ensureConfigured() {
    if (!_config.hasApiBaseUrl) {
      throw const ApiNotConfiguredFailure();
    }
  }
}

/// Ejecuta una petición autenticada arbitraria para pruebas de 403 (no cierra sesión).
Future<T> runAuthorizedRequest<T>(
  Dio dio,
  Future<T> Function() action,
) async {
  try {
    return await action();
  } on DioException catch (e) {
    throw mapDioError(e, loginRequest: false);
  }
}

void assertNoSecretsLogged(String label, Object? value) {
  assert(() {
    if (kDebugMode && value is String && value.contains('|')) {
      debugPrint('Evitar logs con tokens: $label');
    }
    return true;
  }());
}
