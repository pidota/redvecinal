import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';
import 'package:red_vecinal/features/chat/application/chat_room_history_controller.dart';
import 'package:red_vecinal/features/chat/data/models/chat_message.dart';

import '../auth/auth_test_support.dart';
import 'chat_history_pagination_test.dart';
import 'chat_test_support.dart';

List<ChatMessage> _range(int from, int to, {int senderId = 2}) {
  return [
    for (var id = from; id <= to; id++)
      ChatMessage.fromJson(sampleMessageJson(id: id, senderId: senderId)),
  ];
}

FakeChatGateway _windowGateway({
  required List<ChatMessage> initial,
  Map<String, ChatMessagePage> extraPages = const {},
  Duration listDelay = Duration.zero,
  Object? listFailure,
}) {
  return FakeChatGateway(
    pages: {
      '1': ChatMessagePage(messages: initial, limit: 30),
      ...extraPages,
    },
    listDelay: listDelay,
    listFailure: listFailure,
  );
}

void main() {
  test('A: ingest 150 y página 111-140 dejan trustedMaxId=140', () async {
    final gateway = _windowGateway(
      initial: _range(101, 110),
      extraPages: {
        '1|110|null|30': ChatMessagePage(messages: _range(111, 140), limit: 30),
      },
    );
    final container = historyContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    container.listen(chatRoomHistoryControllerProvider(1), (_, __) {});
    await container.read(chatRoomHistoryControllerProvider(1).future);
    final notifier = container.read(chatRoomHistoryControllerProvider(1).notifier);
    notifier.ingestConfirmed(
      ChatMessage.fromJson(sampleMessageJson(id: 150, senderId: 1)),
    );
    expect(
      container.read(chatRoomHistoryControllerProvider(1)).requireValue.trustedMaxId,
      110,
    );
    await notifier.refreshNewer();
    final state = container.read(chatRoomHistoryControllerProvider(1)).requireValue;
    expect(state.trustedMaxId, 140);
    expect(state.timeline.byId.containsKey(150), isTrue);
    expect(state.timeline.maxId, 150);
    expect(state.caughtUpNewer, isFalse);
  });

  test('B: segundo refresh 141-150 amplía a 150', () async {
    final gateway = _windowGateway(
      initial: _range(101, 110),
      extraPages: {
        '1|110|null|30': ChatMessagePage(messages: _range(111, 140), limit: 30),
        '1|140|null|30': ChatMessagePage(messages: _range(141, 150), limit: 30),
      },
    );
    final container = historyContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    container.listen(chatRoomHistoryControllerProvider(1), (_, __) {});
    await container.read(chatRoomHistoryControllerProvider(1).future);
    final notifier = container.read(chatRoomHistoryControllerProvider(1).notifier);
    notifier.ingestConfirmed(
      ChatMessage.fromJson(sampleMessageJson(id: 150, senderId: 1)),
    );
    await notifier.refreshNewer();
    await notifier.refreshNewer();
    expect(
      container.read(chatRoomHistoryControllerProvider(1)).requireValue.trustedMaxId,
      150,
    );
  });

  test('C: página vacía conserva 110 pese a ingest 150', () async {
    final gateway = _windowGateway(
      initial: _range(101, 110),
      extraPages: {
        '1|110|null|30': const ChatMessagePage(messages: [], limit: 30),
      },
    );
    final container = historyContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    container.listen(chatRoomHistoryControllerProvider(1), (_, __) {});
    await container.read(chatRoomHistoryControllerProvider(1).future);
    final notifier = container.read(chatRoomHistoryControllerProvider(1).notifier);
    notifier.ingestConfirmed(
      ChatMessage.fromJson(sampleMessageJson(id: 150, senderId: 1)),
    );
    await notifier.refreshNewer();
    final state = container.read(chatRoomHistoryControllerProvider(1)).requireValue;
    expect(state.trustedMaxId, 110);
    expect(state.caughtUpNewer, isTrue);
    expect(state.timeline.byId.containsKey(150), isTrue);
  });

  test('D: página llena limit=30 no salta a 150', () async {
    final gateway = _windowGateway(
      initial: _range(101, 110),
      extraPages: {
        '1|110|null|30': ChatMessagePage(messages: _range(111, 140), limit: 30),
      },
    );
    final container = historyContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    container.listen(chatRoomHistoryControllerProvider(1), (_, __) {});
    await container.read(chatRoomHistoryControllerProvider(1).future);
    container.read(chatRoomHistoryControllerProvider(1).notifier).ingestConfirmed(
          ChatMessage.fromJson(sampleMessageJson(id: 150, senderId: 1)),
        );
    await container.read(chatRoomHistoryControllerProvider(1).notifier).refreshNewer();
    expect(
      container.read(chatRoomHistoryControllerProvider(1)).requireValue.trustedMaxId,
      140,
    );
  });

  test('E: IDs no consecutivos 114,119,125', () async {
    final gateway = _windowGateway(
      initial: _range(101, 110),
      extraPages: {
        '1|110|null|30': ChatMessagePage(
          messages: [
            ChatMessage.fromJson(sampleMessageJson(id: 114, senderId: 2)),
            ChatMessage.fromJson(sampleMessageJson(id: 119, senderId: 2)),
            ChatMessage.fromJson(sampleMessageJson(id: 125, senderId: 2)),
          ],
          limit: 30,
        ),
      },
    );
    final container = historyContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    container.listen(chatRoomHistoryControllerProvider(1), (_, __) {});
    await container.read(chatRoomHistoryControllerProvider(1).future);
    await container.read(chatRoomHistoryControllerProvider(1).notifier).refreshNewer();
    expect(
      container.read(chatRoomHistoryControllerProvider(1)).requireValue.trustedMaxId,
      125,
    );
  });

  test('F: respuesta antigua no reduce trustedMaxId', () async {
    final gateway = _StaleNewerGateway();
    final container = historyContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    container.listen(chatRoomHistoryControllerProvider(1), (_, __) {});
    await container.read(chatRoomHistoryControllerProvider(1).future);
    final notifier = container.read(chatRoomHistoryControllerProvider(1).notifier);
    final first = notifier.refreshNewer();
    final second = notifier.refreshNewer();
    await Future.wait([first, second]);
    expect(
      container.read(chatRoomHistoryControllerProvider(1)).requireValue.trustedMaxId,
      140,
    );
  });

  test('I: cambio de usuario descarta refreshNewer en vuelo', () async {
    final gateway = _windowGateway(
      initial: _range(101, 110),
      extraPages: {
        '1|110|null|30': ChatMessagePage(messages: _range(111, 140), limit: 30),
      },
      listDelay: const Duration(milliseconds: 40),
    );
    final container = historyContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser(id: 1));
    container.listen(chatRoomHistoryControllerProvider(1), (_, __) {});
    await container.read(chatRoomHistoryControllerProvider(1).future);
    final pending =
        container.read(chatRoomHistoryControllerProvider(1).notifier).refreshNewer();
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser(id: 2, email: 'otro@test.com'));
    await pending;
    await container.read(chatRoomHistoryControllerProvider(1).future);
    final state = container.read(chatRoomHistoryControllerProvider(1)).requireValue;
    expect(state.trustedMaxId, 110);
    expect(state.timeline.byId.containsKey(140), isFalse);
    expect(state.timeline.maxId, 110);
  });

  test('I: logout durante refreshNewer no amplía trustedMaxId', () async {
    final gateway = _windowGateway(
      initial: _range(101, 110),
      extraPages: {
        '1|110|null|30': ChatMessagePage(messages: _range(111, 140), limit: 30),
      },
      listDelay: const Duration(milliseconds: 40),
    );
    final container = historyContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    container.listen(chatRoomHistoryControllerProvider(1), (_, __) {});
    await container.read(chatRoomHistoryControllerProvider(1).future);
    final pending =
        container.read(chatRoomHistoryControllerProvider(1).notifier).refreshNewer();
    await container.read(authControllerProvider.notifier).logout(localOnly: true);
    await pending;
    final state = await container.read(chatRoomHistoryControllerProvider(1).future);
    expect(state.timeline.isEmpty, isTrue);
    expect(state.trustedMaxId, isNull);
  });

  test('I: 401 en refreshNewer no amplía trustedMaxId', () async {
    final gateway = _ExpiredNewerGateway();
    final container = historyContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    container.listen(chatRoomHistoryControllerProvider(1), (_, __) {});
    await container.read(chatRoomHistoryControllerProvider(1).future);
    await container.read(chatRoomHistoryControllerProvider(1).notifier).refreshNewer();
    final state = container.read(chatRoomHistoryControllerProvider(1)).requireValue;
    expect(state.timeline.isEmpty, isTrue);
    expect(state.trustedMaxId, isNull);
  });

  test('I: 403 en refreshNewer revoca sin ampliar', () async {
    final gateway = _ForbiddenNewerGateway();
    final container = historyContainer(gateway);
    addTearDown(container.dispose);
    container.read(authControllerProvider.notifier).state =
        AuthAuthenticated(sampleAuthUser());
    container.listen(chatRoomHistoryControllerProvider(1), (_, __) {});
    await container.read(chatRoomHistoryControllerProvider(1).future);
    expect(
      container.read(chatRoomHistoryControllerProvider(1)).requireValue.trustedMaxId,
      110,
    );
    await container.read(chatRoomHistoryControllerProvider(1).notifier).refreshNewer();
    final state = container.read(chatRoomHistoryControllerProvider(1)).requireValue;
    expect(state.accessRevoked, isTrue);
    expect(state.trustedMaxId, isNull);
  });
}

class _StaleNewerGateway extends FakeChatGateway {
  int _newerCalls = 0;

  @override
  Future<ChatMessagePage> listMessages({
    required int roomId,
    int? afterId,
    int? beforeId,
    int limit = 30,
    CancelToken? cancelToken,
  }) async {
    if (afterId == null) {
      return ChatMessagePage(messages: _range(101, 110), limit: limit);
    }
    _newerCalls++;
    if (_newerCalls == 1) {
      await Future<void>.delayed(const Duration(milliseconds: 40));
      return ChatMessagePage(messages: _range(111, 125), limit: limit);
    }
    return ChatMessagePage(messages: _range(111, 140), limit: limit);
  }
}

class _ExpiredNewerGateway extends FakeChatGateway {
  @override
  Future<ChatMessagePage> listMessages({
    required int roomId,
    int? afterId,
    int? beforeId,
    int limit = 30,
    CancelToken? cancelToken,
  }) async {
    if (afterId != null) {
      throw const ApiSessionExpiredFailure();
    }
    return ChatMessagePage(messages: _range(101, 110), limit: limit);
  }
}

class _ForbiddenNewerGateway extends FakeChatGateway {
  @override
  Future<ChatMessagePage> listMessages({
    required int roomId,
    int? afterId,
    int? beforeId,
    int limit = 30,
    CancelToken? cancelToken,
  }) async {
    if (afterId != null) {
      throw const ApiForbiddenFailure();
    }
    return ChatMessagePage(messages: _range(101, 110), limit: limit);
  }
}
