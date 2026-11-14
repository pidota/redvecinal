import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../auth/auth_test_support.dart';

void main() {
  test('uploadPostAttachment usa multipart y HTTP 201', () async {
    Map<String, dynamic>? captured;
    final dio = Dio(
      BaseOptions(
        baseUrl: '${testAppConfig.apiBaseUrl}/api/v1',
        validateStatus: (_) => true,
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          if (options.path == '/posts/5/attachments' &&
              options.method == 'POST') {
            expect(options.contentType, contains('multipart'));
            captured =
                options.data is FormData
                    ? (options.data as FormData).fields
                        .map((e) => MapEntry(e.key, e.value))
                        .toList()
                        .fold<Map<String, dynamic>>({}, (m, e) {
                          m[e.key] = e.value;
                          return m;
                        })
                    : null;
            handler.resolve(
              Response<Map<String, dynamic>>(
                requestOptions: options,
                statusCode: 201,
                data: {
                  'id': 12,
                  'revision_id': 33,
                  'original_display_name': 'a.pdf',
                  'mime_type': 'application/pdf',
                  'size_bytes': 42,
                },
              ),
            );
            return;
          }
          handler.next(options);
        },
      ),
    );

    final repo = PostRepository(dio, testAppConfig);
    final result = await repo.uploadPostAttachment(
      postId: 5,
      revisionId: 33,
      filePath: fixtureUploadPdfPath(),
      filename: 'a.pdf',
      mimeType: 'application/pdf',
    );
    expect(result.id, 12);
    expect(result.revisionId, 33);
    expect(captured?['revision_id'], '33');
  });

  test('uploadPostAttachment 422', () async {
    final dio = Dio(
      BaseOptions(
        baseUrl: '${testAppConfig.apiBaseUrl}/api/v1',
        validateStatus: (_) => true,
      ),
    );
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 422,
              data: {'message': 'Tipo de archivo no permitido.'},
            ),
          );
        },
      ),
    );
    final repo = PostRepository(dio, testAppConfig);
    await expectLater(
      repo.uploadPostAttachment(
        postId: 1,
        revisionId: 1,
        filePath: fixtureUploadPdfPath(),
        filename: 'x.bin',
        mimeType: 'application/octet-stream',
      ),
      throwsA(isA<ApiValidationFailure>()),
    );
  });
}

String fixtureUploadPdfPath() {
  return 'test/fixtures/tiny_upload.pdf';
}
