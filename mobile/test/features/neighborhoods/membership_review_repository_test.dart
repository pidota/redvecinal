import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/neighborhoods/data/membership_request_repository.dart';
import '../auth/auth_test_support.dart';
import 'membership_request_test_support.dart';
import 'neighborhood_test_support.dart';

MembershipRequestRepository buildRepo(Interceptor interceptor) {
  final dio = Dio(BaseOptions(baseUrl: testAppConfig.apiBaseUrl))..interceptors.add(interceptor);
  return MembershipRequestRepository(dio, testAppConfig);
}

void main() {
  test('reviewable groups 200', () async {
    final repo = buildRepo(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.path.endsWith('/me/reviewable-groups')) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': [sampleGroupJson(id: 7)],
                'meta': {'current_page': 1, 'last_page': 1},
              },
            ),
          );
          return;
        }
        handler.next(options);
      },
    ));

    final page = await repo.reviewableGroups();
    expect(page.items.single.id, 7);
  });

  test('group requests pending con requester', () async {
    final repo = buildRepo(InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: {
              'data': [
                sampleMembershipRequestJson(id: 10, groupId: 3, includeRequester: true),
              ],
              'meta': {'current_page': 1, 'last_page': 1},
            },
          ),
        );
      },
    ));

    final page = await repo.groupRequests(groupId: 3, status: 'pending');
    expect(page.items.single.requester?.name, 'Vecino solicitante');
  });

  test('approve 200', () async {
    final repo = buildRepo(InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 200,
            data: {'data': sampleMembershipRequestJson(status: 'approved')},
          ),
        );
      },
    ));

    final result = await repo.approve(5, reviewNote: 'Bienvenido');
    expect(result.status, 'approved');
  });

  test('approve 409', () async {
    final repo = buildRepo(InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 409,
            data: {'message': 'Solo se pueden aprobar solicitudes pendientes.'},
          ),
        );
      },
    ));

    expect(() => repo.approve(1), throwsA(isA<ApiConflictFailure>()));
  });
}
