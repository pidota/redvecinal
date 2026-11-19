import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/posts/data/models/post_moderation_review.dart';
import 'package:red_vecinal/features/posts/data/post_moderation_failure.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import 'post_test_support.dart';

void main() {
  const config = AppConfig(
    appName: 'Test',
    environment: 'test',
    apiBaseUrl: 'http://test.api/v1',
  );

  group('listPendingPosts', () {
    test('GET cola 200 con PostResource', () async {
      final dio = _dio(config);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.path, '/groups/5/posts/pending');
            expect(options.queryParameters['page'], 1);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': [pendingQueuePostJson(id: 11)],
                  'meta': {'current_page': 1, 'last_page': 1},
                  'links': {},
                },
              ),
            );
          },
        ),
      );

      final page = await PostRepository(
        dio,
        config,
      ).listPendingPosts(groupId: 5);
      expect(page.items, hasLength(1));
      expect(page.items.first.status, 'pending');
      expect(
        PostModerationReview.fromFeedPost(page.items.first)?.pendingTitle,
        'Propuesta pendiente',
      );
    });

    test('cola vacía', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'GET /groups/5/posts/pending': Response(
          requestOptions: RequestOptions(path: '/groups/5/posts/pending'),
          statusCode: 200,
          data: {
            'data': [],
            'meta': {'current_page': 1, 'last_page': 1},
            'links': {},
          },
        ),
      });

      final page = await PostRepository(
        dio,
        config,
      ).listPendingPosts(groupId: 5);
      expect(page.items, isEmpty);
      expect(page.hasMore, isFalse);
    });

    test('paginación', () async {
      final dio = _dio(config);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final page = options.queryParameters['page'] as int? ?? 1;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data':
                      page == 1
                          ? [pendingQueuePostJson(id: 1)]
                          : [pendingQueuePostJson(id: 2, title: 'Página 2')],
                  'meta': {'current_page': page, 'last_page': 2},
                  'links': {},
                },
              ),
            );
          },
        ),
      );

      final repo = PostRepository(dio, config);
      final p1 = await repo.listPendingPosts(groupId: 5, page: 1);
      final p2 = await repo.listPendingPosts(groupId: 5, page: 2);
      expect(p1.hasMore, isTrue);
      expect(p1.items.first.id, 1);
      expect(p2.currentPage, 2);
      expect(p2.items.first.pendingContent?.title, 'Página 2');
    });

    test('enmienda published con pending_content', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'GET /groups/5/posts/pending': Response(
          requestOptions: RequestOptions(path: '/groups/5/posts/pending'),
          statusCode: 200,
          data: {
            'data': [pendingAmendmentPostJson(id: 40)],
            'meta': {'current_page': 1, 'last_page': 1},
            'links': {},
          },
        ),
      });

      final post =
          (await PostRepository(
            dio,
            config,
          ).listPendingPosts(groupId: 5)).items.single;
      final review = PostModerationReview.fromFeedPost(post);
      expect(post.status, 'published');
      expect(review?.isAmendment, isTrue);
      expect(review?.pendingTitle, 'Título enmienda');
      expect(review?.publishedTitle, 'Título publicado');
    });

    test('adjuntos pendientes separados', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'GET /groups/5/posts/pending': Response(
          requestOptions: RequestOptions(path: '/groups/5/posts/pending'),
          statusCode: 200,
          data: {
            'data': [pendingAmendmentPostJson(id: 41)],
            'meta': {'current_page': 1, 'last_page': 1},
            'links': {},
          },
        ),
      });

      final post =
          (await PostRepository(
            dio,
            config,
          ).listPendingPosts(groupId: 5)).items.single;
      expect(post.attachments, isNotEmpty);
      expect(post.pendingAttachments, isNotEmpty);
      expect(
        post.attachments.map((a) => a.id),
        isNot(contains(post.pendingAttachments.first.id)),
      );
    });

    test('401', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'GET /groups/5/posts/pending': Response(
          requestOptions: RequestOptions(path: '/groups/5/posts/pending'),
          statusCode: 401,
          data: {'message': 'Unauthenticated.'},
        ),
      });

      await expectLater(
        PostRepository(dio, config).listPendingPosts(groupId: 5),
        throwsA(isA<ApiSessionExpiredFailure>()),
      );
    });

    test('403', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'GET /groups/5/posts/pending': Response(
          requestOptions: RequestOptions(path: '/groups/5/posts/pending'),
          statusCode: 403,
          data: {'message': 'denegado'},
        ),
      });

      await expectLater(
        PostRepository(dio, config).listPendingPosts(groupId: 5),
        throwsA(isA<ApiForbiddenFailure>()),
      );
    });

    test('404', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'GET /groups/5/posts/pending': Response(
          requestOptions: RequestOptions(path: '/groups/5/posts/pending'),
          statusCode: 404,
          data: {'message': 'no'},
        ),
      });

      await expectLater(
        PostRepository(dio, config).listPendingPosts(groupId: 5),
        throwsA(isA<ApiNotFoundFailure>()),
      );
    });

    test('timeout', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _TimeoutAdapter();

      await expectLater(
        PostRepository(dio, config).listPendingPosts(groupId: 5),
        throwsA(isA<ApiTimeoutFailure>()),
      );
    });

    test('network failure', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _NetworkErrorAdapter();

      await expectLater(
        PostRepository(dio, config).listPendingPosts(groupId: 5),
        throwsA(isA<ApiNetworkFailure>()),
      );
    });

    test('HTTP 500', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'GET /groups/5/posts/pending': Response(
          requestOptions: RequestOptions(path: '/groups/5/posts/pending'),
          statusCode: 500,
          data: {'message': 'error'},
        ),
      });

      await expectLater(
        PostRepository(dio, config).listPendingPosts(groupId: 5),
        throwsA(isA<ApiServerFailure>()),
      );
    });
  });

  group('approvePost', () {
    test('approve 200 sin body', () async {
      final dio = _dio(config);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.method, 'POST');
            expect(options.path, '/posts/9/approve');
            expect(options.data, isNull);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'data': sampleCommunityPostJson(id: 9)},
              ),
            );
          },
        ),
      );

      final detail = await PostRepository(dio, config).approvePost(postId: 9);
      expect(detail.id, 9);
      expect(detail.status, 'published');
    });

    test('approve 403', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'POST /posts/9/approve': Response(
          requestOptions: RequestOptions(path: '/posts/9/approve'),
          statusCode: 403,
          data: {'message': 'denegado'},
        ),
      });

      await expectLater(
        PostRepository(dio, config).approvePost(postId: 9),
        throwsA(isA<ApiForbiddenFailure>()),
      );
    });

    test('approve 422 dominio', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'POST /posts/9/approve': Response(
          requestOptions: RequestOptions(path: '/posts/9/approve'),
          statusCode: 422,
          data: {'message': 'No hay una revisión pendiente para aprobar.'},
        ),
      });

      try {
        await PostRepository(dio, config).approvePost(postId: 9);
        fail('expected throw');
      } on ApiValidationFailure catch (e) {
        expect(isPostModerationDomainFailure(e), isTrue);
      }
    });
  });

  group('rejectPost', () {
    test('reject 200 con rejection_reason', () async {
      final dio = _dio(config);
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.path, '/posts/12/reject');
            expect(options.data, {
              'rejection_reason': 'No cumple las normas de la junta.',
            });
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': () {
                    final json = pendingQueuePostJson(id: 12);
                    json['status'] = 'rejected';
                    return json;
                  }(),
                },
              ),
            );
          },
        ),
      );

      final detail = await PostRepository(dio, config).rejectPost(
        postId: 12,
        rejectionReason: 'No cumple las normas de la junta.',
      );
      expect(detail.status, 'rejected');
    });

    test('motivo vacío validación local', () async {
      final repo = PostRepository(_dio(config), config);
      try {
        await repo.rejectPost(postId: 1, rejectionReason: '   ');
        fail('expected throw');
      } on ApiValidationFailure catch (e) {
        expect(isPostModerationDomainFailure(e), isFalse);
        expect(e.fieldErrors.containsKey('rejection_reason'), isTrue);
      }
    });

    test('motivo mayor a 2000 validación local', () async {
      final repo = PostRepository(_dio(config), config);
      final long = 'x' * 2001;
      try {
        await repo.rejectPost(postId: 1, rejectionReason: long);
        fail('expected throw');
      } on ApiValidationFailure catch (e) {
        expect(isPostModerationDomainFailure(e), isFalse);
      }
    });

    test('reject 422 validación servidor', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'POST /posts/3/reject': Response(
          requestOptions: RequestOptions(path: '/posts/3/reject'),
          statusCode: 422,
          data: {
            'message': 'The rejection reason field is required.',
            'errors': {
              'rejection_reason': ['The rejection reason field is required.'],
            },
          },
        ),
      });

      try {
        await PostRepository(
          dio,
          config,
        ).rejectPost(postId: 3, rejectionReason: 'Motivo válido');
        fail('expected throw');
      } on ApiValidationFailure catch (e) {
        expect(isPostModerationDomainFailure(e), isFalse);
        expect(e.fieldErrors['rejection_reason'], isNotEmpty);
      }
    });

    test('reject 422 dominio', () async {
      final dio = _dio(config);
      dio.httpClientAdapter = _MapAdapter({
        'POST /posts/3/reject': Response(
          requestOptions: RequestOptions(path: '/posts/3/reject'),
          statusCode: 422,
          data: {'message': 'No hay una revisión pendiente para rechazar.'},
        ),
      });

      try {
        await PostRepository(
          dio,
          config,
        ).rejectPost(postId: 3, rejectionReason: 'Motivo');
        fail('expected throw');
      } on ApiValidationFailure catch (e) {
        expect(isPostModerationDomainFailure(e), isTrue);
      }
    });
  });

  test('sin regresión listPosts', () async {
    final dio = _dio(config);
    dio.httpClientAdapter = _MapAdapter({
      'GET /posts': Response(
        requestOptions: RequestOptions(path: '/posts'),
        statusCode: 200,
        data: {
          'data': [sampleCommunityPostJson()],
          'meta': {'current_page': 1, 'last_page': 1},
          'links': {},
        },
      ),
    });

    final page = await PostRepository(dio, config).listPosts();
    expect(page.items.single.id, 1);
  });

  test('sin regresión getPost', () async {
    final dio = _dio(config);
    dio.httpClientAdapter = _MapAdapter({
      'GET /posts/8': Response(
        requestOptions: RequestOptions(path: '/posts/8'),
        statusCode: 200,
        data: {'data': sampleCommunityPostJson(id: 8)},
      ),
    });

    final detail = await PostRepository(dio, config).getPost(8);
    expect(detail.id, 8);
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
