import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

void main() {
  const config = AppConfig(
    appName: 'Test',
    environment: 'test',
    apiBaseUrl: 'http://test.api/v1',
  );

  test('setReaction like', () async {
    final dio = _dio(config);
    dio.httpClientAdapter = _MapAdapter({
      'PUT /posts/3/reactions': Response(
        requestOptions: RequestOptions(path: '/posts/3/reactions'),
        statusCode: 200,
        data: {'id': 9, 'post_id': 3, 'type': 'like'},
      ),
    });

    final record = await PostRepository(dio, config).setReaction(postId: 3);
    expect(record.type, 'like');
  });

  test('removeReaction deleted true', () async {
    final dio = _dio(config);
    dio.httpClientAdapter = _MapAdapter({
      'DELETE /posts/1/reactions': Response(
        requestOptions: RequestOptions(path: '/posts/1/reactions'),
        statusCode: 200,
        data: {'deleted': true},
      ),
    });

    final deleted = await PostRepository(dio, config).removeReaction(postId: 1);
    expect(deleted, isTrue);
  });

  test('setReaction 401', () async {
    final dio = _dio(config);
    dio.httpClientAdapter = _MapAdapter({
      'PUT /posts/1/reactions': Response(
        requestOptions: RequestOptions(path: '/posts/1/reactions'),
        statusCode: 401,
        data: {'message': 'Unauthenticated.'},
      ),
    });

    await expectLater(
      PostRepository(dio, config).setReaction(postId: 1),
      throwsA(isA<ApiSessionExpiredFailure>()),
    );
  });

  test('removeReaction 403', () async {
    final dio = _dio(config);
    dio.httpClientAdapter = _MapAdapter({
      'DELETE /posts/2/reactions': Response(
        requestOptions: RequestOptions(path: '/posts/2/reactions'),
        statusCode: 403,
        data: {'message': 'denegado'},
      ),
    });

    await expectLater(
      PostRepository(dio, config).removeReaction(postId: 2),
      throwsA(isA<ApiForbiddenFailure>()),
    );
  });

  test('setReaction 404', () async {
    final dio = _dio(config);
    dio.httpClientAdapter = _MapAdapter({
      'PUT /posts/8/reactions': Response(
        requestOptions: RequestOptions(path: '/posts/8/reactions'),
        statusCode: 404,
        data: {'message': 'no'},
      ),
    });

    await expectLater(
      PostRepository(dio, config).setReaction(postId: 8),
      throwsA(isA<ApiNotFoundFailure>()),
    );
  });

  test('setReaction 422', () async {
    final dio = _dio(config);
    dio.httpClientAdapter = _MapAdapter({
      'PUT /posts/1/reactions': Response(
        requestOptions: RequestOptions(path: '/posts/1/reactions'),
        statusCode: 422,
        data: {'message': 'No se permiten reacciones en esta publicación.'},
      ),
    });

    await expectLater(
      PostRepository(dio, config).setReaction(postId: 1),
      throwsA(isA<ApiValidationFailure>()),
    );
  });

  test('removeReaction error de red', () async {
    final dio = _dio(config);
    dio.httpClientAdapter = _ThrowingAdapter();

    await expectLater(
      PostRepository(dio, config).removeReaction(postId: 1),
      throwsA(isA<ApiNetworkFailure>()),
    );
  });
}

Dio _dio(AppConfig config) {
  return Dio(
    BaseOptions(
      baseUrl: config.apiBaseUrl,
      validateStatus: (status) => status != null && status < 500,
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

class _ThrowingAdapter implements HttpClientAdapter {
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
