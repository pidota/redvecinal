import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/chat/data/chat_api_exception.dart';
import 'package:red_vecinal/features/chat/data/chat_repository.dart';
import 'package:red_vecinal/features/chat/data/models/chat_enums.dart';

import 'chat_test_support.dart';

const _config = AppConfig(
  appName: 'Test',
  environment: 'test',
  apiBaseUrl: 'http://test.api/v1',
);

void main() {
  group('ChatRepository', () {
    test('lista salas 200', () async {
      final dio = _dio();
      dio.httpClientAdapter = _JsonAdapter({
        'GET /chat/rooms': (
          200,
          {'data': [sampleRoomJson(), sampleRoomJson(id: 2, municipalityId: 11)]},
        ),
      });
      final rooms = await ChatRepository(dio, _config).listRooms();
      expect(rooms, hasLength(2));
      expect(rooms.first.status, ChatRoomStatus.active);
      expect(rooms.last.municipalityId, 11);
    });

    test('historial con after_id y before_id', () async {
      final dio = _dio();
      late RequestOptions captured;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured = options;
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {
                  'data': [
                    sampleMessageJson(id: 11),
                    sampleMessageJson(id: 12),
                  ],
                },
              ),
            );
          },
        ),
      );
      final page = await ChatRepository(dio, _config).listMessages(
        roomId: 1,
        afterId: 10,
        beforeId: 20,
        limit: 50,
      );
      expect(captured.path, '/chat/rooms/1/messages');
      expect(captured.queryParameters['after_id'], 10);
      expect(captured.queryParameters['before_id'], 20);
      expect(captured.queryParameters['limit'], 50);
      expect(page.messages.map((m) => m.id), [11, 12]);
    });

    test('descarta mensajes de otra sala en el JSON', () async {
      final dio = _dio();
      dio.httpClientAdapter = _JsonAdapter({
        'GET /chat/rooms/1/messages': (
          200,
          {
            'data': [
              sampleMessageJson(id: 1, roomId: 1),
              sampleMessageJson(id: 2, roomId: 9),
            ],
          },
        ),
      });
      final page = await ChatRepository(dio, _config).listMessages(roomId: 1);
      expect(page.messages, hasLength(1));
      expect(page.messages.single.chatRoomId, 1);
    });

    test('envío 201 con client_message_id', () async {
      final dio = _dio();
      late Map<String, dynamic> body;
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.method, 'POST');
            expect(options.path, '/chat/rooms/1/messages');
            body = Map<String, dynamic>.from(options.data as Map);
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 201,
                data: {'data': sampleMessageJson(body: 'Hola')},
              ),
            );
          },
        ),
      );
      const uuid = '550e8400-e29b-41d4-a716-446655440000';
      final result = await ChatRepository(dio, _config).sendMessage(
        roomId: 1,
        body: 'Hola',
        clientMessageId: uuid,
      );
      expect(body['client_message_id'], uuid);
      expect(result.message.body, 'Hola');
    });

    test('UUID inválida no llama POST', () async {
      var calls = 0;
      final dio = _dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            calls++;
            handler.next(options);
          },
        ),
      );
      await expectLater(
        ChatRepository(dio, _config).sendMessage(
          roomId: 1,
          body: 'Hola',
          clientMessageId: 'no-uuid',
        ),
        throwsA(isA<ApiValidationFailure>()),
      );
      expect(calls, 0);
    });

    test('lecturas y no leídos', () async {
      final dio = _dio();
      dio.httpClientAdapter = _JsonAdapter({
        'GET /chat/rooms/1/unread-count': (200, {'unread_count': 3}),
        'POST /chat/rooms/1/read': (
          200,
          {
            'last_read_message_id': 8,
            'last_read_at': '2026-11-20T15:00:00.000000Z',
          },
        ),
        'GET /chat/messages/8': (200, {'data': sampleMessageJson(id: 8)}),
      });
      final repo = ChatRepository(dio, _config);
      expect((await repo.unreadCount(1)).unreadCount, 3);
      expect((await repo.markRead(roomId: 1, lastReadMessageId: 8)).lastReadMessageId, 8);
      expect((await repo.getMessage(8)).id, 8);
    });

    test('401 403 404 422 429', () async {
      final repo401 = ChatRepository(_statusDio(401), _config);
      final repo403 = ChatRepository(_statusDio(403), _config);
      final repo404 = ChatRepository(_statusDio(404), _config);
      final repo422 = ChatRepository(_statusDio(422), _config);
      final repo429 = ChatRepository(_statusDio(429), _config);
      await expectLater(repo401.listRooms(), throwsA(isA<ApiSessionExpiredFailure>()));
      await expectLater(
        repo403.listMessages(roomId: 1),
        throwsA(isA<ApiForbiddenFailure>()),
      );
      await expectLater(repo404.getMessage(9), throwsA(isA<ApiNotFoundFailure>()));
      await expectLater(
        repo422.sendMessage(
          roomId: 1,
          body: 'x',
          clientMessageId: '550e8400-e29b-41d4-a716-446655440000',
        ),
        throwsA(isA<ApiValidationFailure>()),
      );
      await expectLater(
        repo429.sendMessage(
          roomId: 1,
          body: 'x',
          clientMessageId: '550e8400-e29b-41d4-a716-446655440000',
        ),
        throwsA(isA<ApiRateLimitedFailure>()),
      );
    });

    test('timeout', () async {
      final dio = _dio();
      dio.httpClientAdapter = _TimeoutAdapter();
      await expectLater(
        ChatRepository(dio, _config).listRooms(),
        throwsA(isA<ApiTimeoutFailure>()),
      );
    });

    test('sin conexión', () async {
      final dio = _dio();
      dio.httpClientAdapter = _NetworkAdapter();
      await expectLater(
        ChatRepository(dio, _config).listRooms(),
        throwsA(isA<ApiNetworkFailure>()),
      );
    });

    test('JSON malformado', () async {
      final dio = _dio();
      dio.httpClientAdapter = _JsonAdapter({
        'GET /chat/rooms': (200, {'data': 'no-lista'}),
      });
      await expectLater(
        ChatRepository(dio, _config).listRooms(),
        throwsA(isA<ChatApiException>()),
      );
    });

    test('un solo POST en timeout de envío', () async {
      var calls = 0;
      final dio = _dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            calls++;
            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.receiveTimeout,
              ),
            );
          },
        ),
      );
      await expectLater(
        ChatRepository(dio, _config).sendMessage(
          roomId: 1,
          body: 'Hola',
          clientMessageId: '550e8400-e29b-41d4-a716-446655440000',
        ),
        throwsA(isA<ApiTimeoutFailure>()),
      );
      expect(calls, 1);
    });
  });
}

Dio _dio() {
  return Dio(
    BaseOptions(
      baseUrl: _config.apiBaseUrl,
      validateStatus: (status) => status != null && status < 600,
    ),
  );
}

Dio _statusDio(int status) {
  final dio = _dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: status,
            data: {
              'message': 'error',
              if (status == 422) 'errors': {'body': ['inválido']},
            },
            headers: Headers.fromMap({
              if (status == 429) 'retry-after': ['12'],
            }),
          ),
        );
      },
    ),
  );
  return dio;
}

class _JsonAdapter implements HttpClientAdapter {
  _JsonAdapter(this.responses);

  final Map<String, (int, Object?)> responses;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final key = '${options.method} ${options.path}';
    final mapped = responses[key];
    if (mapped == null) {
      return ResponseBody.fromString('not found', 404);
    }
    return ResponseBody.fromString(
      jsonEncode(mapped.$2),
      mapped.$1,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }
}

class _TimeoutAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.receiveTimeout,
    );
  }
}

class _NetworkAdapter implements HttpClientAdapter {
  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    throw DioException(
      requestOptions: options,
      type: DioExceptionType.connectionError,
    );
  }
}
