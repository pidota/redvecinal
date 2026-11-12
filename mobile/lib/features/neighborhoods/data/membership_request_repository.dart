import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_failure.dart';
import 'models/membership_request.dart';
import 'models/neighborhood_group.dart';
import 'models/paginated_membership_requests.dart';

abstract class MembershipRequestGateway {
  Future<NeighborhoodGroup> membershipContext(int groupId);

  Future<MembershipRequest> submit({required int groupId, String? requestNote});

  Future<PaginatedMembershipRequests> myRequests({int page = 1});

  Future<void> cancel(int requestId);
}

final membershipRequestRepositoryProvider = Provider<MembershipRequestGateway>((ref) {
  return MembershipRequestRepository(
    ref.watch(dioProvider),
    ref.watch(appConfigProvider),
  );
});

class MembershipRequestRepository implements MembershipRequestGateway {
  MembershipRequestRepository(this._dio, this._config);

  final Dio _dio;
  final AppConfig _config;

  @override
  Future<NeighborhoodGroup> membershipContext(int groupId) async {
    _ensureConfigured();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/groups/$groupId/membership-context',
      );
      return _parseGroupResponse(response);
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  @override
  Future<MembershipRequest> submit({required int groupId, String? requestNote}) async {
    _ensureConfigured();
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/groups/$groupId/membership-requests',
        data: {
          if (requestNote != null && requestNote.trim().isNotEmpty)
            'request_note': requestNote.trim(),
        },
      );

      final status = response.statusCode ?? 0;
      if (status == 201) {
        return _parseRequestResponse(response);
      }

      throw DioException(requestOptions: response.requestOptions, response: response);
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  @override
  Future<PaginatedMembershipRequests> myRequests({int page = 1}) async {
    _ensureConfigured();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/me/membership-requests',
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

      return PaginatedMembershipRequests(
        items: _parseRequestList(payload['data']),
        currentPage: currentPage,
        lastPage: lastPage,
      );
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  @override
  Future<void> cancel(int requestId) async {
    _ensureConfigured();
    try {
      final response = await _dio.delete<void>('/me/membership-requests/$requestId');
      final status = response.statusCode ?? 0;
      if (status == 204) {
        return;
      }
      throw DioException(requestOptions: response.requestOptions, response: response);
    } on DioException catch (e) {
      throw mapDioError(e, loginRequest: false);
    }
  }

  NeighborhoodGroup _parseGroupResponse(Response<Map<String, dynamic>> response) {
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
  }

  MembershipRequest _parseRequestResponse(Response<Map<String, dynamic>> response) {
    final payload = response.data;
    if (payload == null) {
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

    return MembershipRequest.fromJson(raw);
  }

  List<MembershipRequest> _parseRequestList(dynamic raw) {
    if (raw is! List) {
      return const [];
    }

    return raw
        .whereType<Map<String, dynamic>>()
        .map(MembershipRequest.fromJson)
        .toList();
  }

  void _ensureConfigured() {
    if (!_config.hasApiBaseUrl) {
      throw const ApiNotConfiguredFailure();
    }
  }
}
