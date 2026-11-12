import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_failure.dart';
import 'models/neighborhood_group.dart';
import 'models/paginated_neighborhood_groups.dart';

abstract class NeighborhoodGateway {
  Future<List<NeighborhoodGroup>> myGroups();

  Future<PaginatedNeighborhoodGroups> listGroups({int page = 1});

  Future<NeighborhoodGroup> groupDetail(int groupId);
}

final neighborhoodRepositoryProvider = Provider<NeighborhoodGateway>((ref) {
  return NeighborhoodRepository(
    ref.watch(dioProvider),
    ref.watch(appConfigProvider),
  );
});

class NeighborhoodRepository implements NeighborhoodGateway {
  NeighborhoodRepository(this._dio, this._config);

  final Dio _dio;
  final AppConfig _config;

  @override
  Future<List<NeighborhoodGroup>> myGroups() async {
    _ensureConfigured();
    try {
      final response = await _dio.get<Map<String, dynamic>>('/me/groups');

      final payload = response.data;
      if (response.statusCode != 200 || payload == null) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
        );
      }

      return _parseGroupList(payload['data']);
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  @override
  Future<PaginatedNeighborhoodGroups> listGroups({int page = 1}) async {
    _ensureConfigured();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/groups',
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
      final currentPage = meta is Map<String, dynamic> ? (meta['current_page'] as int? ?? page) : page;
      final lastPage = meta is Map<String, dynamic> ? (meta['last_page'] as int? ?? currentPage) : currentPage;

      return PaginatedNeighborhoodGroups(
        items: _parseGroupList(payload['data']),
        currentPage: currentPage,
        lastPage: lastPage,
      );
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  @override
  Future<NeighborhoodGroup> groupDetail(int groupId) async {
    _ensureConfigured();
    try {
      final response = await _dio.get<Map<String, dynamic>>('/groups/$groupId');

      final payload = response.data;
      if (response.statusCode != 200 || payload == null) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
        );
      }

      final raw = payload['data'] ?? payload;
      if (raw is! Map<String, dynamic>) {
        throw DioException(
          requestOptions: response.requestOptions,
          response: response,
        );
      }

      return NeighborhoodGroup.fromJson(raw);
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  List<NeighborhoodGroup> _parseGroupList(dynamic raw) {
    if (raw is! List) {
      return const [];
    }

    return raw
        .whereType<Map<String, dynamic>>()
        .map(NeighborhoodGroup.fromJson)
        .toList();
  }

  void _ensureConfigured() {
    if (!_config.hasApiBaseUrl) {
      throw const ApiNotConfiguredFailure();
    }
  }
}
