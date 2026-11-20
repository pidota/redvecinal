import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/api_failure.dart';
import 'chat_api_exception.dart';
import 'chat_client_message_id.dart';
import 'chat_json.dart';
import 'models/chat_message.dart';
import 'models/chat_room.dart';

abstract class ChatGateway {
  Future<List<ChatRoom>> listRooms({CancelToken? cancelToken});

  Future<ChatMessagePage> listMessages({
    required int roomId,
    int? afterId,
    int? beforeId,
    int limit = 30,
    CancelToken? cancelToken,
  });

  Future<ChatSendResult> sendMessage({
    required int roomId,
    required String body,
    required String clientMessageId,
    CancelToken? cancelToken,
  });

  Future<ChatMessage> getMessage(int messageId, {CancelToken? cancelToken});

  Future<ChatReadResult> markRead({
    required int roomId,
    int? lastReadMessageId,
    CancelToken? cancelToken,
  });

  Future<ChatUnreadCount> unreadCount(int roomId, {CancelToken? cancelToken});

  Future<ChatMessage> editMessage({
    required int messageId,
    required String body,
    CancelToken? cancelToken,
  });

  Future<ChatMessage> deleteMessage(int messageId, {CancelToken? cancelToken});

  Future<ChatMessage> hideMessage({
    required int messageId,
    String? reason,
    CancelToken? cancelToken,
  });

  Future<int> reportMessage({
    required int messageId,
    required String reasonCode,
    String? details,
    CancelToken? cancelToken,
  });
}

final chatRepositoryProvider = Provider<ChatGateway>((ref) {
  return ChatRepository(ref.watch(dioProvider), ref.watch(appConfigProvider));
});

class ChatRepository implements ChatGateway {
  ChatRepository(this._dio, this._config);

  static const int defaultLimit = 30;
  static const int maxLimit = 100;
  static const int maxBodyLength = 4000;

  final Dio _dio;
  final AppConfig _config;

  @override
  Future<List<ChatRoom>> listRooms({CancelToken? cancelToken}) async {
    _ensureConfigured();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/chat/rooms',
        cancelToken: cancelToken,
      );
      final payload = _requirePayload(response, 200);
      return unwrapResourceList(payload).map(ChatRoom.fromJson).toList();
    } on ChatApiException {
      rethrow;
    } on ChatRequestCancelled {
      rethrow;
    } on DioException catch (e) {
      throw _mapped(e);
    } on ApiFailure {
      rethrow;
    } on Object {
      throw const ChatApiException();
    }
  }

  @override
  Future<ChatMessagePage> listMessages({
    required int roomId,
    int? afterId,
    int? beforeId,
    int limit = defaultLimit,
    CancelToken? cancelToken,
  }) async {
    _ensureConfigured();
    final clamped = limit.clamp(1, maxLimit);
    final query = <String, dynamic>{'limit': clamped};
    if (afterId != null) {
      query['after_id'] = afterId;
    }
    if (beforeId != null) {
      query['before_id'] = beforeId;
    }

    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/chat/rooms/$roomId/messages',
        queryParameters: query,
        cancelToken: cancelToken,
      );
      final payload = _requirePayload(response, 200);
      final messages = unwrapResourceList(payload)
          .map(ChatMessage.fromJson)
          .where((message) => message.chatRoomId == roomId)
          .toList()
        ..sort((a, b) => a.id.compareTo(b.id));
      return ChatMessagePage(messages: messages, limit: clamped);
    } on ChatApiException {
      rethrow;
    } on ChatRequestCancelled {
      rethrow;
    } on DioException catch (e) {
      throw _mapped(e);
    } on ApiFailure {
      rethrow;
    } on Object {
      throw const ChatApiException();
    }
  }

  @override
  Future<ChatSendResult> sendMessage({
    required int roomId,
    required String body,
    required String clientMessageId,
    CancelToken? cancelToken,
  }) async {
    _ensureConfigured();
    if (!isChatClientMessageUuidV4(clientMessageId)) {
      throw const ApiValidationFailure(
        {
          'client_message_id': ['UUID inválido.'],
        },
        'client_message_id inválido.',
      );
    }

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/chat/rooms/$roomId/messages',
        data: {
          'body': body,
          'client_message_id': clientMessageId,
        },
        cancelToken: cancelToken,
      );
      final payload = _requirePayload(response, 201);
      final message = ChatMessage.fromJson(unwrapResourceData(payload));
      if (message.chatRoomId != roomId) {
        throw const ChatApiException();
      }
      return ChatSendResult(message: message);
    } on ChatApiException {
      rethrow;
    } on ChatRequestCancelled {
      rethrow;
    } on DioException catch (e) {
      throw _mapped(e);
    } on ApiFailure {
      rethrow;
    } on Object {
      throw const ChatApiException();
    }
  }

  @override
  Future<ChatMessage> getMessage(int messageId, {CancelToken? cancelToken}) async {
    _ensureConfigured();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/chat/messages/$messageId',
        cancelToken: cancelToken,
      );
      final payload = _requirePayload(response, 200);
      return ChatMessage.fromJson(unwrapResourceData(payload));
    } on ChatApiException {
      rethrow;
    } on ChatRequestCancelled {
      rethrow;
    } on DioException catch (e) {
      throw _mapped(e);
    } on ApiFailure {
      rethrow;
    } on Object {
      throw const ChatApiException();
    }
  }

  @override
  Future<ChatReadResult> markRead({
    required int roomId,
    int? lastReadMessageId,
    CancelToken? cancelToken,
  }) async {
    _ensureConfigured();
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/chat/rooms/$roomId/read',
        data: {
          'last_read_message_id': lastReadMessageId,
        },
        cancelToken: cancelToken,
      );
      final payload = _requirePayload(response, 200);
      return ChatReadResult.fromJson(payload);
    } on ChatApiException {
      rethrow;
    } on ChatRequestCancelled {
      rethrow;
    } on DioException catch (e) {
      throw _mapped(e);
    } on ApiFailure {
      rethrow;
    } on Object {
      throw const ChatApiException();
    }
  }

  @override
  Future<ChatUnreadCount> unreadCount(int roomId, {CancelToken? cancelToken}) async {
    _ensureConfigured();
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/chat/rooms/$roomId/unread-count',
        cancelToken: cancelToken,
      );
      final payload = _requirePayload(response, 200);
      return ChatUnreadCount.fromJson(payload);
    } on ChatApiException {
      rethrow;
    } on ChatRequestCancelled {
      rethrow;
    } on DioException catch (e) {
      throw _mapped(e);
    } on ApiFailure {
      rethrow;
    } on Object {
      throw const ChatApiException();
    }
  }

  @override
  Future<ChatMessage> editMessage({
    required int messageId,
    required String body,
    CancelToken? cancelToken,
  }) async {
    _ensureConfigured();
    try {
      final response = await _dio.patch<Map<String, dynamic>>(
        '/chat/messages/$messageId',
        data: {'body': body},
        cancelToken: cancelToken,
      );
      final payload = _requirePayload(response, 200);
      return ChatMessage.fromJson(unwrapResourceData(payload));
    } on ChatApiException {
      rethrow;
    } on ChatRequestCancelled {
      rethrow;
    } on DioException catch (e) {
      throw _mapped(e);
    } on ApiFailure {
      rethrow;
    } on Object {
      throw const ChatApiException();
    }
  }

  @override
  Future<ChatMessage> deleteMessage(int messageId, {CancelToken? cancelToken}) async {
    _ensureConfigured();
    try {
      final response = await _dio.delete<Map<String, dynamic>>(
        '/chat/messages/$messageId',
        cancelToken: cancelToken,
      );
      final payload = _requirePayload(response, 200);
      return ChatMessage.fromJson(unwrapResourceData(payload));
    } on ChatApiException {
      rethrow;
    } on ChatRequestCancelled {
      rethrow;
    } on DioException catch (e) {
      throw _mapped(e);
    } on ApiFailure {
      rethrow;
    } on Object {
      throw const ChatApiException();
    }
  }

  @override
  Future<ChatMessage> hideMessage({
    required int messageId,
    String? reason,
    CancelToken? cancelToken,
  }) async {
    _ensureConfigured();
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/chat/messages/$messageId/hide',
        data: {
          if (reason != null) 'reason': reason,
        },
        cancelToken: cancelToken,
      );
      final payload = _requirePayload(response, 200);
      return ChatMessage.fromJson(unwrapResourceData(payload));
    } on ChatApiException {
      rethrow;
    } on ChatRequestCancelled {
      rethrow;
    } on DioException catch (e) {
      throw _mapped(e);
    } on ApiFailure {
      rethrow;
    } on Object {
      throw const ChatApiException();
    }
  }

  @override
  Future<int> reportMessage({
    required int messageId,
    required String reasonCode,
    String? details,
    CancelToken? cancelToken,
  }) async {
    _ensureConfigured();
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/chat/messages/$messageId/report',
        data: {
          'reason_code': reasonCode,
          if (details != null) 'details': details,
        },
        cancelToken: cancelToken,
      );
      final payload = _requirePayload(response, 201);
      return parseRequiredInt(payload['id']);
    } on ChatApiException {
      rethrow;
    } on ChatRequestCancelled {
      rethrow;
    } on DioException catch (e) {
      throw _mapped(e);
    } on ApiFailure {
      rethrow;
    } on Object {
      throw const ChatApiException();
    }
  }

  Map<String, dynamic> _requirePayload(
    Response<Map<String, dynamic>> response,
    int expectedStatus,
  ) {
    final payload = response.data;
    if (response.statusCode != expectedStatus || payload == null) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
      );
    }
    return payload;
  }

  Never _mapped(DioException error) {
    if (error.type == DioExceptionType.cancel) {
      throw const ChatRequestCancelled();
    }
    throw mapDioError(error, loginRequest: false);
  }

  void _ensureConfigured() {
    if (!_config.hasApiBaseUrl) {
      throw const ApiUnexpectedFailure();
    }
  }
}
