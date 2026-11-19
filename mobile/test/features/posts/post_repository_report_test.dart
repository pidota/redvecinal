import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/posts/data/post_report_validation.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

void main() {
  const config = AppConfig(
    appName: 'Test',
    environment: 'test',
    apiBaseUrl: 'http://test.api/v1',
  );

  Response<Map<String, dynamic>> ok201Response({Map<String, dynamic>? extra}) {
    return Response(
      requestOptions: RequestOptions(path: '/posts/7/reports'),
      statusCode: 201,
      data: {'id': 42, 'status': 'open', ...?extra},
    );
  }

  group('reportPost HTTP', () {
    test('POST correcto', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'POST /posts/7/reports': ok201Response(),
      });

      final result = await PostRepository(
        dio,
        config,
      ).reportPost(postId: 7, reasonCode: 'spam');
      expect(result.id, 42);
      expect(result.status, 'open');
    });

    test('URL correcta', () async {
      final dio = _dio(config);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.method, 'POST');
            expect(options.path, '/posts/9/reports');
            handler.resolve(ok201Response());
          },
        ),
      );

      await PostRepository(
        dio,
        config,
      ).reportPost(postId: 9, reasonCode: 'spam');
    });

    test('token mediante cliente existente', () async {
      final dio = _dio(config);
      dio.options.headers['Authorization'] = 'Bearer test-token';
      var calls = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            calls++;
            expect(options.headers['Authorization'], 'Bearer test-token');
            handler.resolve(ok201Response());
          },
        ),
      );

      await PostRepository(
        dio,
        config,
      ).reportPost(postId: 1, reasonCode: 'spam');
      expect(calls, 1);
    });

    test('reason_code spam en cuerpo', () async {
      final dio = _dio(config);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final data = options.data as Map<String, dynamic>;
            expect(data['reason_code'], 'spam');
            handler.resolve(ok201Response());
          },
        ),
      );

      await PostRepository(
        dio,
        config,
      ).reportPost(postId: 1, reasonCode: 'spam');
    });

    test('reason_code inappropriate en cuerpo', () async {
      final dio = _dio(config);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final data = options.data as Map<String, dynamic>;
            expect(data['reason_code'], 'inappropriate');
            handler.resolve(ok201Response());
          },
        ),
      );

      await PostRepository(
        dio,
        config,
      ).reportPost(postId: 1, reasonCode: 'inappropriate');
    });

    test('details opcional omitido', () async {
      final dio = _dio(config);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final data = options.data as Map<String, dynamic>;
            expect(data.containsKey('details'), isFalse);
            handler.resolve(ok201Response());
          },
        ),
      );

      await PostRepository(
        dio,
        config,
      ).reportPost(postId: 1, reasonCode: 'spam');
    });

    test('details presente', () async {
      final dio = _dio(config);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final data = options.data as Map<String, dynamic>;
            expect(data['details'], 'Contenido dudoso');
            handler.resolve(ok201Response());
          },
        ),
      );

      await PostRepository(
        dio,
        config,
      ).reportPost(postId: 1, reasonCode: 'spam', details: 'Contenido dudoso');
    });

    test('HTTP 201', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'POST /posts/3/reports': ok201Response(),
      });

      final result = await PostRepository(
        dio,
        config,
      ).reportPost(postId: 3, reasonCode: 'spam');
      expect(result.id, greaterThan(0));
    });

    test('parseo de id', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'POST /posts/3/reports': Response(
          requestOptions: RequestOptions(path: '/posts/3/reports'),
          statusCode: 201,
          data: {'id': 99, 'status': 'open'},
        ),
      });

      final result = await PostRepository(
        dio,
        config,
      ).reportPost(postId: 3, reasonCode: 'spam');
      expect(result.id, 99);
    });

    test('parseo de status', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'POST /posts/3/reports': Response(
          requestOptions: RequestOptions(path: '/posts/3/reports'),
          statusCode: 201,
          data: {'id': 1, 'status': 'open'},
        ),
      });

      final result = await PostRepository(
        dio,
        config,
      ).reportPost(postId: 3, reasonCode: 'spam');
      expect(result.status, 'open');
    });

    test('401', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'POST /posts/1/reports': Response(
          requestOptions: RequestOptions(path: '/posts/1/reports'),
          statusCode: 401,
          data: {'message': 'Unauthenticated.'},
        ),
      });

      await expectLater(
        PostRepository(dio, config).reportPost(postId: 1, reasonCode: 'spam'),
        throwsA(isA<ApiSessionExpiredFailure>()),
      );
    });

    test('403', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'POST /posts/1/reports': Response(
          requestOptions: RequestOptions(path: '/posts/1/reports'),
          statusCode: 403,
          data: {'message': 'denegado'},
        ),
      });

      await expectLater(
        PostRepository(dio, config).reportPost(postId: 1, reasonCode: 'spam'),
        throwsA(isA<ApiForbiddenFailure>()),
      );
    });

    test('404', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'POST /posts/8/reports': Response(
          requestOptions: RequestOptions(path: '/posts/8/reports'),
          statusCode: 404,
          data: {'message': 'no'},
        ),
      });

      await expectLater(
        PostRepository(dio, config).reportPost(postId: 8, reasonCode: 'spam'),
        throwsA(isA<ApiNotFoundFailure>()),
      );
    });

    test('422 por reason_code', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'POST /posts/1/reports': Response(
          requestOptions: RequestOptions(path: '/posts/1/reports'),
          statusCode: 422,
          data: {
            'message': 'The reason code field is required.',
            'errors': {
              'reason_code': ['The reason code field is required.'],
            },
          },
        ),
      });

      try {
        await PostRepository(
          dio,
          config,
        ).reportPost(postId: 1, reasonCode: 'spam');
        fail('expected throw');
      } on ApiValidationFailure catch (e) {
        expect(e.fieldErrors.containsKey('reason_code'), isTrue);
      }
    });

    test('422 por details', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'POST /posts/1/reports': Response(
          requestOptions: RequestOptions(path: '/posts/1/reports'),
          statusCode: 422,
          data: {
            'message': 'too long',
            'errors': {
              'details': [
                'The details must not be greater than 2000 characters.',
              ],
            },
          },
        ),
      });

      try {
        await PostRepository(
          dio,
          config,
        ).reportPost(postId: 1, reasonCode: 'spam', details: 'ok');
        fail('expected throw');
      } on ApiValidationFailure catch (e) {
        expect(e.fieldErrors.containsKey('details'), isTrue);
      }
    });

    test('timeout', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _TimeoutAdapter();

      await expectLater(
        PostRepository(dio, config).reportPost(postId: 1, reasonCode: 'spam'),
        throwsA(isA<ApiTimeoutFailure>()),
      );
    });

    test('error de red', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _NetworkErrorAdapter();

      await expectLater(
        PostRepository(dio, config).reportPost(postId: 1, reasonCode: 'spam'),
        throwsA(isA<ApiNetworkFailure>()),
      );
    });

    test('HTTP 500', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'POST /posts/1/reports': Response(
          requestOptions: RequestOptions(path: '/posts/1/reports'),
          statusCode: 500,
          data: {'message': 'error'},
        ),
      });

      await expectLater(
        PostRepository(dio, config).reportPost(postId: 1, reasonCode: 'spam'),
        throwsA(isA<ApiServerFailure>()),
      );
    });

    test('HTTP 502 sin reintento', () async {
      final dio = _dio(config);
      var calls = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            calls++;
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 502,
                  data: {'message': 'bad gateway'},
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      await expectLater(
        PostRepository(dio, config).reportPost(postId: 1, reasonCode: 'spam'),
        throwsA(isA<ApiServerFailure>()),
      );
      expect(calls, 1);
    });

    test('HTTP 503 sin reintento', () async {
      final dio = _dio(config);
      var calls = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            calls++;
            handler.reject(
              DioException(
                requestOptions: options,
                response: Response(
                  requestOptions: options,
                  statusCode: 503,
                  data: {'message': 'unavailable'},
                ),
                type: DioExceptionType.badResponse,
              ),
            );
          },
        ),
      );

      await expectLater(
        PostRepository(dio, config).reportPost(postId: 1, reasonCode: 'spam'),
        throwsA(isA<ApiServerFailure>()),
      );
      expect(calls, 1);
    });

    test('ausencia de reintento automático', () async {
      final dio = _dio(config);
      var calls = 0;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            calls++;
            handler.resolve(ok201Response());
          },
        ),
      );

      await PostRepository(
        dio,
        config,
      ).reportPost(postId: 2, reasonCode: 'spam');
      expect(calls, 1);
    });

    test('ausencia de reporter_id en request', () async {
      final dio = _dio(config);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final data = options.data as Map<String, dynamic>;
            expect(data.containsKey('reporter_id'), isFalse);
            expect(data.containsKey('user_id'), isFalse);
            handler.resolve(ok201Response());
          },
        ),
      );

      await PostRepository(
        dio,
        config,
      ).reportPost(postId: 1, reasonCode: 'spam');
    });

    test('respuesta sin reporter_id en modelo', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'POST /posts/1/reports': ok201Response(extra: {'reporter_id': 99}),
      });

      final result = await PostRepository(
        dio,
        config,
      ).reportPost(postId: 1, reasonCode: 'spam');
      expect(result.id, 42);
      expect(result.status, 'open');
    });

    test('respuesta malformada', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'POST /posts/1/reports': Response(
          requestOptions: RequestOptions(path: '/posts/1/reports'),
          statusCode: 201,
          data: {'status': 'open'},
        ),
      });

      await expectLater(
        PostRepository(dio, config).reportPost(postId: 1, reasonCode: 'spam'),
        throwsA(isA<ApiUnexpectedFailure>()),
      );
    });
  });

  group('validatePostReportInput', () {
    test('motivo vacío', () {
      expect(
        validatePostReportInput(reasonCode: ''),
        isA<ApiValidationFailure>(),
      );
    });

    test('motivo solo espacios', () {
      final failure = validatePostReportInput(reasonCode: '   ');
      expect(failure, isA<ApiValidationFailure>());
      expect(failure!.fieldErrors.containsKey('reason_code'), isTrue);
    });

    test('motivo superior a 60', () {
      final code = 'x' * 61;
      final failure = validatePostReportInput(reasonCode: code);
      expect(failure, isA<ApiValidationFailure>());
    });

    test('details superior a 2000', () {
      final failure = validatePostReportInput(
        reasonCode: 'spam',
        details: 'd' * 2001,
      );
      expect(failure, isA<ApiValidationFailure>());
      expect(failure!.fieldErrors.containsKey('details'), isTrue);
    });
  });

  test('incertidumbre timeout/red', () {
    expect(isPostReportOutcomeUncertain(const ApiNetworkFailure()), isTrue);
    expect(isPostReportOutcomeUncertain(const ApiTimeoutFailure()), isTrue);
    expect(isPostReportOutcomeUncertain(const ApiServerFailure()), isTrue);
    expect(isPostReportOutcomeUncertain(const ApiUnexpectedFailure()), isTrue);
    expect(isPostReportOutcomeUncertain(const ApiForbiddenFailure()), isFalse);
  });
}

Dio _dio(AppConfig config) {
  return Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      validateStatus: (status) => status != null && status < 600,
    ),
  );
}

class _MapAdapter implements HttpClientAdapter {
  _MapAdapter(this.responses);

  final Map<String, Response<dynamic>> responses;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? cancelFuture,
    Future<void>? onCancel,
  ) async {
    final key = '${options.method} ${options.path}';
    final response = responses[key];
    if (response == null) {
      return ResponseBody.fromString('not found', 404);
    }

    return ResponseBody.fromString(
      jsonEncode(response.data),
      response.statusCode ?? 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _NetworkErrorAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? cancelFuture,
    Future<void>? onCancel,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
    );
  }
}

class _TimeoutAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? cancelFuture,
    Future<void>? onCancel,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.receiveTimeout,
    );
  }
}
