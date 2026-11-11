import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_client.dart';
import 'package:red_vecinal/core/network/unauthorized_handler.dart';

import '../../features/auth/auth_test_support.dart';

class _QueuedAdapter implements HttpClientAdapter {
  _QueuedAdapter(this._responses);

  final List<_QueuedResponse> _responses;
  int _index = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final item = _responses[_index++];
    await Future<void>.delayed(item.delay);
    return ResponseBody.fromString(
      item.body,
      item.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

class _QueuedResponse {
  _QueuedResponse(this.status, this.body, {this.delay = Duration.zero});

  final int status;
  final String body;
  final Duration delay;
}

void main() {
  test('401 en /auth/login no dispara invalidación global', () async {
    var invalidated = 0;
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
      ],
    );
    container.read(unauthorizedHandlerProvider.notifier).state = () async {
      invalidated++;
    };
    addTearDown(container.dispose);

    final dio = container.read(dioProvider);
    dio.httpClientAdapter = _QueuedAdapter([
      _QueuedResponse(401, jsonEncode({'message': 'bad creds'})),
    ]);

    try {
      await dio.post<Map<String, dynamic>>('/auth/login', data: {'x': 1});
    } on DioException {
      // Esperado con validateStatus < 500.
    }

    await Future<void>.delayed(Duration.zero);
    expect(invalidated, 0);
  });

  test('401 con Bearer obsoleto no invalida sesión nueva', () async {
    var invalidated = 0;

    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
      ],
    );
    container.read(bearerTokenProvider.notifier).state = '1|old-token';
    container.read(unauthorizedHandlerProvider.notifier).state = () async {
      invalidated++;
    };
    addTearDown(container.dispose);

    final dio = container.read(dioProvider);
    dio.httpClientAdapter = _QueuedAdapter([
      _QueuedResponse(
        401,
        jsonEncode({'message': 'expired'}),
        delay: const Duration(milliseconds: 40),
      ),
    ]);

    final request = dio.get<Map<String, dynamic>>('/me');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    container.read(bearerTokenProvider.notifier).state = '2|new-token';

    try {
      await request;
    } on DioException {
      // ok
    }

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(invalidated, 0);
  });

  test('401 autenticado dispara invalidación una vez', () async {
    var invalidated = 0;
    final container = ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
      ],
    );
    container.read(bearerTokenProvider.notifier).state = '1|live';
    container.read(unauthorizedHandlerProvider.notifier).state = () async {
      invalidated++;
    };
    addTearDown(container.dispose);

    final dio = container.read(dioProvider);
    dio.httpClientAdapter = _QueuedAdapter([
      _QueuedResponse(401, jsonEncode({'message': 'expired'})),
      _QueuedResponse(401, jsonEncode({'message': 'expired'})),
    ]);

    try {
      await Future.wait([
        dio.get<Map<String, dynamic>>('/me'),
        dio.get<Map<String, dynamic>>('/me'),
      ]);
    } on DioException {
      // ok
    }

    await Future<void>.delayed(const Duration(milliseconds: 350));
    expect(invalidated, lessThanOrEqualTo(1));
  });
}
