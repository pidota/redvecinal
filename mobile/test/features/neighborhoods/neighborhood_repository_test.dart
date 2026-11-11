import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_client.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/neighborhoods/data/neighborhood_repository.dart';

import '../auth/auth_test_support.dart';

void main() {
  test('401 en myGroups mapea a ApiSessionExpiredFailure', () async {
    final dio = Dio(BaseOptions(baseUrl: testAppConfig.apiBaseUrl));
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.reject(
          DioException(
            requestOptions: options,
            response: Response(
              requestOptions: options,
              statusCode: 401,
              data: const {'message': 'Unauthenticated.'},
            ),
          ),
        );
      },
    ));

    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        dioProvider.overrideWithValue(dio),
      ],
    );
    addTearDown(container.dispose);

    final repo = container.read(neighborhoodRepositoryProvider);

    await expectLater(
      repo.myGroups(),
      throwsA(isA<ApiSessionExpiredFailure>()),
    );
  });
}
