import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_failure.dart';
import 'models/neighborhood_group.dart';

abstract class NeighborhoodGateway {
  Future<List<NeighborhoodGroup>> myGroups();
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

      final raw = payload['data'];
      if (raw is! List) {
        return const [];
      }

      return raw
          .whereType<Map<String, dynamic>>()
          .map(NeighborhoodGroup.fromJson)
          .toList();
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  void _ensureConfigured() {
    if (!_config.hasApiBaseUrl) {
      throw const ApiNotConfiguredFailure();
    }
  }
}
