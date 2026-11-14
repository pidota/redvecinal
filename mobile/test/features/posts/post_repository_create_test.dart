import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

Dio _statusDio(
  void Function(RequestOptions options, Response<Map<String, dynamic>> response)
  onPost,
) {
  final dio = Dio(
    BaseOptions(
      baseUrl: '${testAppConfig.apiBaseUrl}/api/v1',
      validateStatus: (_) => true,
    ),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final response = Response<Map<String, dynamic>>(
          requestOptions: options,
        );
        onPost(options, response);
        handler.resolve(response);
      },
    ),
  );
  return dio;
}

void main() {
  test('listPostCategories parsea lista', () async {
    final dio = Dio(
      BaseOptions(
        baseUrl: '${testAppConfig.apiBaseUrl}/api/v1',
        validateStatus: (_) => true,
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/post-categories') {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': [
                    {
                      'id': 2,
                      'slug': 'aviso-comunitario',
                      'name': 'Aviso',
                      'default_audience': 'group',
                      'sort_order': 1,
                      'is_system': true,
                    },
                  ],
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
    final items = await repo.listPostCategories(audience: 'group');
    expect(items.single.id, 2);
  });

  test('createCommunityPost acepta HTTP 200', () async {
    final dio = Dio(
      BaseOptions(
        baseUrl: '${testAppConfig.apiBaseUrl}/api/v1',
        validateStatus: (_) => true,
      ),
    );

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/posts' && options.method == 'POST') {
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 200,
                data: {'data': sampleCommunityPostJson(id: 40)},
              ),
            );
            return;
          }
          handler.next(options);
        },
      ),
    );

    final repo = PostRepository(dio, testAppConfig);
    final detail = await repo.createCommunityPost(
      neighborhoodGroupId: 2,
      categoryId: 2,
      title: 'T',
      body: 'C',
    );
    expect(detail.id, 40);
  });

  test('createCommunityPost 401', () async {
    final repo = PostRepository(
      _statusDio((options, response) {
        response.statusCode = 401;
        response.data = {'message': 'Unauthenticated.'};
      }),
      testAppConfig,
    );

    await expectLater(
      repo.createCommunityPost(
        neighborhoodGroupId: 2,
        categoryId: 2,
        title: 'T',
        body: 'C',
      ),
      throwsA(isA<ApiSessionExpiredFailure>()),
    );
  });

  test('createCommunityPost 403', () async {
    final repo = PostRepository(
      _statusDio((options, response) {
        response.statusCode = 403;
        response.data = {'message': 'denegado'};
      }),
      testAppConfig,
    );

    await expectLater(
      repo.createCommunityPost(
        neighborhoodGroupId: 2,
        categoryId: 2,
        title: 'T',
        body: 'C',
      ),
      throwsA(isA<ApiForbiddenFailure>()),
    );
  });

  test('createCommunityPost 422', () async {
    final repo = PostRepository(
      _statusDio((options, response) {
        response.statusCode = 422;
        response.data = {
          'message': 'validation',
          'errors': {
            'title': ['required'],
          },
        };
      }),
      testAppConfig,
    );

    await expectLater(
      repo.createCommunityPost(
        neighborhoodGroupId: 2,
        categoryId: 2,
        title: 'T',
        body: 'C',
      ),
      throwsA(isA<ApiValidationFailure>()),
    );
  });

  test('submitPost 401', () async {
    final repo = PostRepository(
      _statusDio((options, response) {
        if (options.path == '/posts/5/submit') {
          response.statusCode = 401;
          response.data = {'message': 'Unauthenticated.'};
        } else {
          response.statusCode = 404;
          response.data = {'message': 'not found'};
        }
      }),
      testAppConfig,
    );

    await expectLater(
      repo.submitPost(5),
      throwsA(isA<ApiSessionExpiredFailure>()),
    );
  });

  test('submitPost 403', () async {
    final repo = PostRepository(
      _statusDio((options, response) {
        response.statusCode = 403;
        response.data = {'message': 'denegado'};
      }),
      testAppConfig,
    );

    await expectLater(repo.submitPost(5), throwsA(isA<ApiForbiddenFailure>()));
  });

  test('submitPost 422', () async {
    final repo = PostRepository(
      _statusDio((options, response) {
        response.statusCode = 422;
        response.data = {
          'message': 'validation',
          'errors': {
            'status': ['invalid'],
          },
        };
      }),
      testAppConfig,
    );

    await expectLater(repo.submitPost(5), throwsA(isA<ApiValidationFailure>()));
  });
}
