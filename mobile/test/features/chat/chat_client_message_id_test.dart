import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/chat/data/chat_client_message_id.dart';

void main() {
  test('UUID v4 válida y distinta en cada generación', () {
    final first = generateChatClientMessageId(Random(1));
    final second = generateChatClientMessageId(Random(2));
    expect(isChatClientMessageUuidV4(first), isTrue);
    expect(isChatClientMessageUuidV4(second), isTrue);
    expect(first, isNot(second));
  });

  test('rechaza UUID no v4', () {
    expect(isChatClientMessageUuidV4('not-a-uuid'), isFalse);
    expect(
      isChatClientMessageUuidV4('550e8400-e29b-11d4-a716-446655440000'),
      isFalse,
    );
  });
}
