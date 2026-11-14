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

  test('getPost parsea data', () async {
    final dio = Dio(
      BaseOptions(
        baseUrl: config.apiBaseUrl,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    dio.httpClientAdapter = _MapAdapter({
      'GET /posts/5': Response(
        requestOptions: RequestOptions(path: '/posts/5'),
        statusCode: 200,
        data: {'data': sampleCommunityPostJson(id: 5)},
      ),
    });

    final detail = await PostRepository(dio, config).getPost(5);
    expect(detail.id, 5);
    expect(detail.attachments, isNotEmpty);
  });

  test('getPost 404', () async {
    final dio = Dio(
      BaseOptions(
        baseUrl: config.apiBaseUrl,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    dio.httpClientAdapter = _MapAdapter({
      'GET /posts/9': Response(
        requestOptions: RequestOptions(path: '/posts/9'),
        statusCode: 404,
        data: {'message': 'no'},
      ),
    });

    await expectLater(
      PostRepository(dio, config).getPost(9),
      throwsA(isA<ApiNotFoundFailure>()),
    );
  });

  test('downloadAttachment bytes', () async {
    final dio = Dio(
      BaseOptions(
        baseUrl: config.apiBaseUrl,
        validateStatus: (status) => status != null && status < 500,
      ),
    );
    dio.httpClientAdapter = _MapAdapter({
      'GET /posts/1/attachments/7': Response(
        requestOptions: RequestOptions(path: '/posts/1/attachments/7'),
        statusCode: 200,
        data: [9, 8, 7],
      ),
    });

    final bytes = await PostRepository(
      dio,
      config,
    ).downloadAttachment(postId: 1, attachmentId: 7);
    expect(bytes, [9, 8, 7]);
  });
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
    if (data is List<int>) {
      return ResponseBody.fromBytes(data, response.statusCode ?? 200);
    }
    return ResponseBody.fromString(
      jsonEncode(data),
      response.statusCode ?? 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}
