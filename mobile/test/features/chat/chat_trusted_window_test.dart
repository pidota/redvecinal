import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/chat/application/chat_trusted_window.dart';
import 'package:red_vecinal/features/chat/data/models/chat_message.dart';

import 'chat_test_support.dart';

List<ChatMessage> _msgs(List<int> ids, {int roomId = 1}) {
  return ids
      .map(
        (id) => ChatMessage.fromJson(
          sampleMessageJson(id: id, roomId: roomId, senderId: 2),
        ),
      )
      .toList();
}

void main() {
  test('página 111-140 desde 110 amplía a 140, no a un ingest 150', () {
    expect(
      advanceTrustedMaxId(
        currentTrustedMaxId: 110,
        requestedAfterId: 110,
        pageMessages: _msgs(List<int>.generate(30, (i) => 111 + i)),
        roomId: 1,
      ),
      140,
    );
  });

  test('página vacía no usa mensajes ingeridos', () {
    expect(
      advanceTrustedMaxId(
        currentTrustedMaxId: 110,
        requestedAfterId: 110,
        pageMessages: const [],
        roomId: 1,
      ),
      110,
    );
  });

  test('IDs no consecutivos acreditan el máximo de la página', () {
    expect(
      advanceTrustedMaxId(
        currentTrustedMaxId: 110,
        requestedAfterId: 110,
        pageMessages: _msgs([114, 119, 125]),
        roomId: 1,
      ),
      125,
    );
  });

  test('cursor obsoleto no reduce ni amplía trustedMaxId', () {
    expect(
      advanceTrustedMaxId(
        currentTrustedMaxId: 140,
        requestedAfterId: 110,
        pageMessages: _msgs([111, 125]),
        roomId: 1,
      ),
      140,
    );
  });

  test('mensajes de otra sala no amplían', () {
    expect(
      advanceTrustedMaxId(
        currentTrustedMaxId: 110,
        requestedAfterId: 110,
        pageMessages: _msgs([150], roomId: 9),
        roomId: 1,
      ),
      110,
    );
  });
}
