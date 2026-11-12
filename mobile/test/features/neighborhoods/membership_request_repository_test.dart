import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/neighborhoods/data/membership_request_repository.dart';

import '../auth/auth_test_support.dart';
import 'neighborhood_test_support.dart';

MembershipRequestRepository buildRepo(Interceptor interceptor) {
  final dio = Dio(BaseOptions(baseUrl: testAppConfig.apiBaseUrl))
    ..interceptors.add(interceptor);
  return MembershipRequestRepository(dio, testAppConfig);
}

void main() {
  test('membership context 200', () async {
    final repo = buildRepo(InterceptorsWrapper(
      onRequest: (options, handler) {
        if (options.path.endsWith('/membership-context')) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {'data': sampleGroupJson(id: 5)},
            ),
          );
          return;
        }
        handler.next(options);
      },
    ));

    final group = await repo.membershipContext(5);
    expect(group.id, 5);
  });

  test('submit 409 mapea conflicto', () async {
    final repo = buildRepo(InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 409,
            data: {'message': 'Ya tienes una solicitud pendiente para esta junta.'},
          ),
        );
      },
    ));

    expect(
      () => repo.submit(groupId: 3),
      throwsA(isA<ApiConflictFailure>()),
    );
  });

  test('422 muestra mensaje del servidor', () async {
    final repo = buildRepo(InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: 422,
            data: {'message': 'Debes esperar 7 días desde el último rechazo.'},
          ),
        );
      },
    ));

    try {
      await repo.submit(groupId: 3);
      fail('expected failure');
    } on ApiValidationFailure catch (e) {
      expect(e.userMessage, contains('7 días'));
    }
  });
}
