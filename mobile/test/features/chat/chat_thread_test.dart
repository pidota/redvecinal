import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/chat/application/chat_outgoing.dart';
import 'package:red_vecinal/features/chat/data/chat_timeline.dart';
import 'package:red_vecinal/features/chat/data/models/chat_enums.dart';
import 'package:red_vecinal/features/chat/data/models/chat_message.dart';
import 'package:red_vecinal/features/chat/presentation/chat_thread.dart';

import 'chat_test_support.dart';

void main() {
  test('hilo combina servidor y pendientes sin duplicar confirmados', () {
    final timeline = const ChatTimeline().merge(
      [
        ChatMessage.fromJson(sampleMessageJson(id: 1, body: 'A')),
        ChatMessage.fromJson(
          sampleMessageJson(id: 2, body: 'B', clientMessageId: 'uuid-1'),
        ),
      ],
      roomId: 1,
    );
    final items = buildChatThreadItems(
      timeline: timeline,
      outgoing: [
        ChatOutgoingMessage(
          userId: 1,
          roomId: 1,
          body: 'B',
          clientMessageId: 'uuid-1',
          status: ChatOutgoingStatus.confirmed,
          confirmed: ChatMessage.fromJson(
            sampleMessageJson(id: 2, body: 'B', clientMessageId: 'uuid-1'),
          ),
        ),
        const ChatOutgoingMessage(
          userId: 1,
          roomId: 1,
          body: 'C',
          clientMessageId: 'uuid-2',
          status: ChatOutgoingStatus.uncertain,
        ),
      ],
    );
    expect(items.where((item) => item.message?.id == 2), hasLength(1));
    expect(items.where((item) => item.outgoing?.clientMessageId == 'uuid-2'), hasLength(1));
    expect(items.where((item) => item.outgoing?.status == ChatOutgoingStatus.confirmed), isEmpty);
  });
}
