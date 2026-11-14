import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import 'post_test_support.dart';

void main() {
  const config = AppConfig(
    appName: 'Test',
    environment: 'test',
    apiBaseUrl: 'http://test.api/v1',
  );

  test('listComments parsea paginación', () async {
    final dio = _dio(config);
    dio.httpClientAdapter = _MapAdapter({
      'GET /posts/3/comments': Response(
        requestOptions: RequestOptions(path: '/posts/3/comments'),
        statusCode: 200,
        data: {
          'data': [sampleCommentJson(postId: 3)],
          'meta': {'current_page': 1, 'last_page': 2},
          'links': {},
        },
      ),
    });

    final page = await PostRepository(dio, config).listComments(postId: 3);
    expect(page.items.single.postId, 3);
    expect(page.lastPage, 2);
    expect(page.hasMore, isTrue);
  });

  test('createComment 201', () async {
    final dio = _dio(config);
    dio.httpClientAdapter = _MapAdapter({
      'POST /posts/1/comments': Response(
        requestOptions: RequestOptions(path: '/posts/1/comments'),
        statusCode: 201,
        data: {'data': sampleCommentJson(body: 'Hola')},
      ),
    });

    final created = await PostRepository(
      dio,
      config,
    ).createComment(postId: 1, body: 'Hola');
    expect(created.body, 'Hola');
  });

  test('listComments 401', () async {
    final dio = _dio(config);
    dio.httpClientAdapter = _MapAdapter({
      'GET /posts/1/comments': Response(
        requestOptions: RequestOptions(path: '/posts/1/comments'),
        statusCode: 401,
        data: {'message': 'Unauthenticated.'},
      ),
    });

    await expectLater(
      PostRepository(dio, config).listComments(postId: 1),
      throwsA(isA<ApiSessionExpiredFailure>()),
    );
  });

  test('createComment 403', () async {
    final dio = _dio(config);
    dio.httpClientAdapter = _MapAdapter({
      'POST /posts/1/comments': Response(
        requestOptions: RequestOptions(path: '/posts/1/comments'),
        statusCode: 403,
        data: {'message': 'denegado'},
      ),
    });

    await expectLater(
      PostRepository(dio, config).createComment(postId: 1, body: 'x'),
      throwsA(isA<ApiForbiddenFailure>()),
    );
  });

  test('listComments 404', () async {
    final dio = _dio(config);
    dio.httpClientAdapter = _MapAdapter({
      'GET /posts/8/comments': Response(
        requestOptions: RequestOptions(path: '/posts/8/comments'),
        statusCode: 404,
        data: {'message': 'no'},
      ),
    });

    await expectLater(
      PostRepository(dio, config).listComments(postId: 8),
      throwsA(isA<ApiNotFoundFailure>()),
    );
  });

  test('createComment 422', () async {
    final dio = _dio(config);
    dio.httpClientAdapter = _MapAdapter({
      'POST /posts/1/comments': Response(
        requestOptions: RequestOptions(path: '/posts/1/comments'),
        statusCode: 422,
        data: {'message': 'No se permiten comentarios en esta publicación.'},
      ),
    });

    await expectLater(
      PostRepository(dio, config).createComment(postId: 1, body: 'x'),
      throwsA(isA<ApiValidationFailure>()),
    );
  });

  test('listComments error de red', () async {
    final dio = Dio(
      BaseOptions(
        baseUrl: config.apiBaseUrl,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    dio.httpClientAdapter = _ThrowingAdapter();

    await expectLater(
      PostRepository(dio, config).listComments(postId: 1),
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

    final data = response.data;
    return ResponseBody.fromString(
      jsonEncode(data),
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
