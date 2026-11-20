import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/chat/data/chat_timeline.dart';
import 'package:red_vecinal/features/chat/data/models/chat_message.dart';

import 'chat_test_support.dart';

void main() {
  test('no duplica por id y conserva el de mayor version', () {
    const timeline = ChatTimeline();
    final first = ChatMessage.fromJson(sampleMessageJson(id: 2, version: 1));
    final updated = ChatMessage.fromJson(
      sampleMessageJson(id: 2, version: 2, body: 'Editado'),
    );
    final merged = timeline.merge([first, updated, first], roomId: 1);
    expect(merged.messages, hasLength(1));
    expect(merged.messages.single.body, 'Editado');
    expect(merged.messages.single.version, 2);
  });

  test('ordena por id y descarta otra sala', () {
    const timeline = ChatTimeline();
    final merged = timeline.merge(
      [
        ChatMessage.fromJson(sampleMessageJson(id: 5, roomId: 1)),
        ChatMessage.fromJson(sampleMessageJson(id: 3, roomId: 1)),
        ChatMessage.fromJson(sampleMessageJson(id: 4, roomId: 99)),
      ],
      roomId: 1,
    );
    expect(merged.messages.map((m) => m.id), [3, 5]);
  });

  test('página vacía no borra el historial', () {
    var timeline = const ChatTimeline().merge(
      [ChatMessage.fromJson(sampleMessageJson(id: 1))],
      roomId: 1,
    );
    timeline = timeline.merge(const [], roomId: 1);
    expect(timeline.messages, hasLength(1));
  });
}
