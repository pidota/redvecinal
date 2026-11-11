import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_config.dart';
import 'api_failure.dart';
import 'session_invalidation_coordinator.dart';
import 'unauthorized_handler.dart';

final sessionInvalidationCoordinatorProvider = Provider<SessionInvalidationCoordinator>((ref) {
  return SessionInvalidationCoordinator(() async {
    final handler = ref.read(unauthorizedHandlerProvider);
    if (handler != null) {
      await handler();
    }
  });
});

final dioProvider = Provider<Dio>((ref) {
  final config = ref.watch(appConfigProvider);
  final coordinator = ref.watch(sessionInvalidationCoordinatorProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: config.hasApiBaseUrl ? config.apiBaseUrl : 'http://invalid.local',
      connectTimeout: config.connectTimeout,
      receiveTimeout: config.receiveTimeout,
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  dio.interceptors.add(_BearerTokenInterceptor(ref));
  dio.interceptors.add(_UnauthorizedInterceptor(ref, coordinator));

  return dio;
});

class _BearerTokenInterceptor extends Interceptor {
  _BearerTokenInterceptor(this._ref);

  final Ref _ref;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    final token = _ref.read(bearerTokenProvider);
    if (token != null && token.isNotEmpty) {
      final base = _ref.read(appConfigProvider).apiBaseUrl;
      if (base.isNotEmpty && options.uri.toString().startsWith(base)) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }
}

class _UnauthorizedInterceptor extends Interceptor {
  _UnauthorizedInterceptor(this._ref, this._coordinator);

  final Ref _ref;
  final SessionInvalidationCoordinator _coordinator;

  @override
  void onResponse(Response<dynamic> response, ResponseInterceptorHandler handler) {
    _maybeInvalidateSession(response.requestOptions, response.statusCode);
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final response = err.response;
    if (response != null) {
      _maybeInvalidateSession(err.requestOptions, response.statusCode);
    }
    handler.next(err);
  }

  void _maybeInvalidateSession(RequestOptions options, int? status) {
    if (status != 401 || options.path.contains('/auth/login')) {
      return;
    }

    final sent = _bearerFrom(options.headers);
    final current = _ref.read(bearerTokenProvider);

    if (sent != null && current != null && sent != current) {
      return;
    }

    _coordinator.handleUnauthorized();
  }

  String? _bearerFrom(Map<String, dynamic> headers) {
    final raw = headers['Authorization'] ?? headers['authorization'];
    if (raw is! String) {
      return null;
    }
    const prefix = 'Bearer ';
    if (raw.startsWith(prefix)) {
      return raw.substring(prefix.length);
    }
    return raw;
  }
}

/// Mapea [DioException] y códigos HTTP a fallos de dominio (sin loguear tokens).
ApiFailure mapDioError(DioException error, {required bool loginRequest}) {
  if (error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.receiveTimeout) {
    return const ApiTimeoutFailure();
  }

  if (error.type == DioExceptionType.connectionError) {
    return const ApiNetworkFailure();
  }

  final response = error.response;
  if (response == null) {
    return const ApiNetworkFailure();
  }

  final status = response.statusCode ?? 0;

  if (status >= 500) {
    return const ApiServerFailure();
  }

  if (status == 401) {
    return loginRequest ? const ApiInvalidCredentialsFailure() : const ApiSessionExpiredFailure();
  }

  if (status == 403) {
    final message = _extractMessage(response.data);
    return ApiForbiddenFailure(message);
  }

  if (status == 422) {
    return ApiValidationFailure(_extractValidationErrors(response.data));
  }

  if (status == 429) {
    return ApiRateLimitedFailure(retryAfter: _parseRetryAfter(response.headers));
  }

  return const ApiUnexpectedFailure();
}

String? _extractMessage(dynamic data) {
  if (data is Map<String, dynamic> && data['message'] is String) {
    return data['message'] as String;
  }
  return null;
}

Map<String, List<String>> _extractValidationErrors(dynamic data) {
  if (data is! Map<String, dynamic>) {
    return const {};
  }
  final errors = data['errors'];
  if (errors is! Map<String, dynamic>) {
    return const {};
  }
  return errors.map((key, value) {
    if (value is List) {
      return MapEntry(key, value.map((e) => e.toString()).toList());
    }
    return MapEntry(key, [value.toString()]);
  });
}

Duration? _parseRetryAfter(dynamic headers) {
  if (headers is! Headers) {
    return null;
  }
  final value = headers.value('retry-after');
  if (value == null) {
    return null;
  }
  final seconds = int.tryParse(value);
  if (seconds != null) {
    return Duration(seconds: seconds);
  }
  return null;
}

/// Token en memoria para el interceptor (no persiste en logs).
final bearerTokenProvider = StateProvider<String?>((ref) => null);

void debugAssertNoTokenLogging() {
  assert(() {
    if (kDebugMode) {
      // Recordatorio: no usar debugPrint con Authorization.
    }
    return true;
  }());
}
