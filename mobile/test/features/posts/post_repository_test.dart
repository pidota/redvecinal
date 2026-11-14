import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_client.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

void main() {
  test('parsea paginación Laravel en listPosts', () async {
    final dio = Dio(BaseOptions(baseUrl: testAppConfig.apiBaseUrl));
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response(
              requestOptions: options,
              statusCode: 200,
              data: {
                'data': [sampleCommunityPostJson()],
                'meta': {'current_page': 1, 'last_page': 3},
                'links': {},
              },
            ),
          );
        },
      ),
    );

    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        dioProvider.overrideWithValue(dio),
      ],
    );
    addTearDown(container.dispose);

    final page = await container.read(postRepositoryProvider).listPosts();
    expect(page.items, hasLength(1));
    expect(page.currentPage, 1);
    expect(page.lastPage, 3);
    expect(page.hasMore, isTrue);
  });
}
