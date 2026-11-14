import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_failure.dart';
import 'models/feed_post.dart';
import 'models/paginated_feed_posts.dart';
import 'models/paginated_post_comments.dart';
import 'models/post_comment.dart';
import 'models/post_detail.dart';
import 'models/post_category.dart';
import 'models/post_attachment_upload_result.dart';
import 'models/post_reaction.dart';

abstract class PostGateway {
  Future<PaginatedFeedPosts> listPosts({
    int page = 1,
    int? neighborhoodGroupId,
  });

  Future<PostDetail> getPost(int postId);

  Future<List<int>> downloadAttachment({
    required int postId,
    required int attachmentId,
    String? relativePath,
  });

  Future<PaginatedPostComments> listComments({
    required int postId,
    int page = 1,
  });

  Future<PostComment> createComment({
    required int postId,
    required String body,
  });

  Future<PostReactionRecord> setReaction({
    required int postId,
    String type = 'like',
  });

  Future<bool> removeReaction({required int postId});

  Future<List<PostCategory>> listPostCategories({String audience = 'group'});

  Future<PostDetail> createCommunityPost({
    required int neighborhoodGroupId,
    required int categoryId,
    required String title,
    required String body,
  });

  Future<PostDetail> submitPost(int postId);

  Future<PostAttachmentUploadResult> uploadPostAttachment({
    required int postId,
    required int revisionId,
    required String filePath,
    required String filename,
    required String mimeType,
    CancelToken? cancelToken,
    void Function(int sent, int total)? onSendProgress,
  });

  Future<PaginatedFeedPosts> listMyPosts({int page = 1});
}

final postRepositoryProvider = Provider<PostGateway>((ref) {
  return PostRepository(ref.watch(dioProvider), ref.watch(appConfigProvider));
});

class PostRepository implements PostGateway {
  PostRepository(this._dio, this._config);

  final Dio _dio;
  final AppConfig _config;

  @override
  Future<PaginatedFeedPosts> listPosts({
    int page = 1,
    int? neighborhoodGroupId,
  }) async {
    _ensureConfigured();

    final query = <String, dynamic>{'page': page};
    if (neighborhoodGroupId != null) {
      query['neighborhood_group_id'] = neighborhoodGroupId;
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/posts',
        queryParameters: query,
      );

      final payload = response.data;
      if (response.statusCode != 200 || payload == null) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
        );
      }

      final meta = payload['meta'];
      final currentPage =
          meta is Map<String, dynamic>
              ? (meta['current_page'] as int? ?? page)
              : page;
      final lastPage =
          meta is Map<String, dynamic>
              ? (meta['last_page'] as int? ?? currentPage)
              : currentPage;

      return PaginatedFeedPosts(
        items: _parsePostList(payload['data']),
        currentPage: currentPage,
        lastPage: lastPage,
      );
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  List<FeedPost> _parsePostList(dynamic raw) {
    if (raw is! List) {
      return const [];
    }

    return raw
        .whereType<Map<String, dynamic>>()
        .map(FeedPost.fromJson)
        .toList();
  }

  @override
  Future<PostDetail> getPost(int postId) async {
    _ensureConfigured();

    try {
      final response = await _dio.get<Map<String, dynamic>>('/posts/$postId');

      final payload = response.data;
      if (response.statusCode == 200 && payload != null) {
        final data = payload['data'];
        if (data is Map<String, dynamic>) {
          return PostDetail.fromJson(data);
        }
      }

      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
      );
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  @override
  Future<List<int>> downloadAttachment({
    required int postId,
    required int attachmentId,
    String? relativePath,
  }) async {
    _ensureConfigured();

    final path = relativePath ?? '/posts/$postId/attachments/$attachmentId';

    try {
      final response = await _dio.get<List<int>>(
        path,
        options: Options(
          responseType: ResponseType.bytes,
          headers: const {'Accept': '*/*'},
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        return response.data!;
      }

      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
      );
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  @override
  Future<PaginatedPostComments> listComments({
    required int postId,
    int page = 1,
  }) async {
    _ensureConfigured();

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/posts/$postId/comments',
        queryParameters: {'page': page},
      );

      final payload = response.data;
      if (response.statusCode != 200 || payload == null) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
        );
      }

      final meta = payload['meta'];
      final currentPage =
          meta is Map<String, dynamic>
              ? (meta['current_page'] as int? ?? page)
              : page;
      final lastPage =
          meta is Map<String, dynamic>
              ? (meta['last_page'] as int? ?? currentPage)
              : currentPage;

      return PaginatedPostComments(
        items: _parseCommentList(payload['data']),
        currentPage: currentPage,
        lastPage: lastPage,
      );
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  @override
  Future<PostComment> createComment({
    required int postId,
    required String body,
  }) async {
    _ensureConfigured();

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/posts/$postId/comments',
        data: {'body': body},
      );

      final status = response.statusCode ?? 0;
      final payload = response.data;
      if (status == 201 && payload != null) {
        final data = payload['data'];
        if (data is Map<String, dynamic>) {
          return PostComment.fromJson(data);
        }
      }

      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
      );
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  List<PostComment> _parseCommentList(dynamic raw) {
    if (raw is! List) {
      return const [];
    }

    return raw
        .whereType<Map<String, dynamic>>()
        .map(PostComment.fromJson)
        .toList();
  }

  @override
  Future<PostReactionRecord> setReaction({
    required int postId,
    String type = 'like',
  }) async {
    _ensureConfigured();

    try {
      final response = await _dio.put<Map<String, dynamic>>(
        '/posts/$postId/reactions',
        data: {'type': type},
      );

      final payload = response.data;
      if (response.statusCode == 200 && payload != null) {
        return PostReactionRecord.fromJson(payload);
      }

      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
      );
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  @override
  Future<bool> removeReaction({required int postId}) async {
    _ensureConfigured();

    try {
      final response = await _dio.delete<Map<String, dynamic>>(
        '/posts/$postId/reactions',
      );

      final payload = response.data;
      if (response.statusCode == 200 && payload != null) {
        return payload['deleted'] == true;
      }

      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
      );
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  @override
  Future<List<PostCategory>> listPostCategories({
    String audience = 'group',
  }) async {
    _ensureConfigured();

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/post-categories',
        queryParameters: {'audience': audience},
      );

      final payload = response.data;
      if (response.statusCode != 200 || payload == null) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
        );
      }

      final raw = payload['data'];
      if (raw is! List) {
        return const [];
      }

      return raw
          .whereType<Map<String, dynamic>>()
          .map(PostCategory.fromJson)
          .toList();
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  @override
  Future<PostDetail> createCommunityPost({
    required int neighborhoodGroupId,
    required int categoryId,
    required String title,
    required String body,
  }) async {
    _ensureConfigured();

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/posts',
        data: {
          'neighborhood_group_id': neighborhoodGroupId,
          'category_id': categoryId,
          'title': title,
          'body': body,
        },
      );

      final status = response.statusCode ?? 0;
      final payload = response.data;
      if (status == 200 && payload != null) {
        final data = payload['data'];
        if (data is Map<String, dynamic>) {
          return PostDetail.fromJson(data);
        }
        if (payload.containsKey('id')) {
          return PostDetail.fromJson(payload);
        }
      }

      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
      );
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  @override
  Future<PostAttachmentUploadResult> uploadPostAttachment({
    required int postId,
    required int revisionId,
    required String filePath,
    required String filename,
    required String mimeType,
    CancelToken? cancelToken,
    void Function(int sent, int total)? onSendProgress,
  }) async {
    _ensureConfigured();

    try {
      final formData = FormData.fromMap({
        'revision_id': revisionId,
        'file': await MultipartFile.fromFile(filePath, filename: filename),
      });

      final response = await _dio.post<Map<String, dynamic>>(
        '/posts/$postId/attachments',
        data: formData,
        cancelToken: cancelToken,
        onSendProgress: onSendProgress,
        options: Options(
          contentType: 'multipart/form-data',
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: const Duration(minutes: 2),
          headers: const {'Accept': 'application/json'},
        ),
      );

      final status = response.statusCode ?? 0;
      final payload = response.data;
      if (status == 201 && payload != null) {
        return PostAttachmentUploadResult.fromJson(payload);
      }

      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
      );
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  @override
  Future<PostDetail> submitPost(int postId) async {
    _ensureConfigured();

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/posts/$postId/submit',
      );

      final status = response.statusCode ?? 0;
      final payload = response.data;
      if (status == 200 && payload != null) {
        final data = payload['data'];
        if (data is Map<String, dynamic>) {
          return PostDetail.fromJson(data);
        }
        if (payload.containsKey('id')) {
          return PostDetail.fromJson(payload);
        }
      }

      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
      );
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  @override
  Future<PaginatedFeedPosts> listMyPosts({int page = 1}) async {
    _ensureConfigured();

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/me/posts',
        queryParameters: {'page': page},
      );

      final payload = response.data;
      if (response.statusCode != 200 || payload == null) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
        );
      }

      final meta = payload['meta'];
      final currentPage =
          meta is Map<String, dynamic>
              ? (meta['current_page'] as int? ?? page)
              : page;
      final lastPage =
          meta is Map<String, dynamic>
              ? (meta['last_page'] as int? ?? currentPage)
              : currentPage;

      return PaginatedFeedPosts(
        items: _parsePostList(payload['data']),
        currentPage: currentPage,
        lastPage: lastPage,
      );
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  void _ensureConfigured() {
    if (!_config.hasApiBaseUrl) {
      throw const ApiUnexpectedFailure();
    }
  }
}
