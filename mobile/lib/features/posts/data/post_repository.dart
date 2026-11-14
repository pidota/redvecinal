import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_failure.dart';
import 'models/feed_post.dart';
import 'models/paginated_feed_posts.dart';

abstract class PostGateway {
  Future<PaginatedFeedPosts> listPosts({
    int page = 1,
    int? neighborhoodGroupId,
  });
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

  void _ensureConfigured() {
    if (!_config.hasApiBaseUrl) {
      throw const ApiUnexpectedFailure();
    }
  }
}
