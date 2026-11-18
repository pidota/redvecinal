import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

void main() {
  test('updatePost PATCH 200', () async {
    final dio = Dio(
      BaseOptions(
        baseUrl: '${testAppConfig.apiBaseUrl}/api/v1',
        validateStatus: (_) => true,
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/posts/5' && options.method == 'PATCH') {
            expect(options.data, {
              'category_id': 2,
              'title': 'Nuevo',
              'body': 'Texto',
            });
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': mineDraftPostJson(
                    id: 5,
                    title: 'Nuevo',
                    body: 'Texto',
                  ),
                },
              ),
            );
            return;
          }
          handler.next(options);
        },
      ),
    );

    final repo = PostRepository(dio, testAppConfig);
    final detail = await repo.updatePost(
      postId: 5,
      categoryId: 2,
      title: 'Nuevo',
      body: 'Texto',
    );
    expect(detail.id, 5);
    expect(detail.workingContent?.title, 'Nuevo');
  });

  test('updatePost 422', () async {
    final dio = Dio(
      BaseOptions(
        baseUrl: '${testAppConfig.apiBaseUrl}/api/v1',
        validateStatus: (_) => true,
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 422,
              data: {'message': 'No se puede editar'},
            ),
          );
        },
      ),
    );
    final repo = PostRepository(dio, testAppConfig);
    await expectLater(
      repo.updatePost(postId: 5, categoryId: 2, title: 'T', body: 'B'),
      throwsA(isA<ApiValidationFailure>()),
    );
  });

  test('updatePost 404', () async {
    final dio = Dio(
      BaseOptions(
        baseUrl: '${testAppConfig.apiBaseUrl}/api/v1',
        validateStatus: (_) => true,
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 404,
            ),
          );
        },
      ),
    );
    final repo = PostRepository(dio, testAppConfig);
    await expectLater(
      repo.updatePost(postId: 5, categoryId: 2, title: 'T', body: 'B'),
      throwsA(isA<ApiNotFoundFailure>()),
    );
  });
}
