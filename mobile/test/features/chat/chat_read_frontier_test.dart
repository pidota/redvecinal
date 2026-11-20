import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/chat/application/chat_read_frontier.dart';
import 'package:red_vecinal/features/chat/data/models/chat_message.dart';

import 'chat_test_support.dart';

List<ChatMessage> others(List<int> ids) {
  return ids
      .map(
        (id) => ChatMessage.fromJson(
          sampleMessageJson(id: id, senderId: 2, body: 'msg-$id'),
        ),
      )
      .toList();
}

void main() {
  test('A: solo 110 presentado no avanza', () {
    final timeline = others([101, 102, 103, 104, 105, 106, 107, 108, 109, 110]);
    expect(
      computeSafeReadFrontier(
        timeline: timeline,
        presentedIds: {110},
        userId: 1,
        roomId: 1,
        confirmedCursor: null,
        hasOlder: false,
      ),
      isNull,
    );
  });

  test('B: frontera completa avanza a 110', () {
    final ids = [101, 102, 103, 104, 105, 106, 107, 108, 109, 110];
    expect(
      computeSafeReadFrontier(
        timeline: others(ids),
        presentedIds: ids.toSet(),
        userId: 1,
        roomId: 1,
        confirmedCursor: null,
        hasOlder: false,
      ),
      110,
    );
  });

  test('C: visibilidad parcial se detiene en el primer pendiente', () {
    expect(
      computeSafeReadFrontier(
        timeline: others([101, 102, 103, 104, 105, 106, 107, 108, 109, 110]),
        presentedIds: {101, 102, 103, 107, 108, 110},
        userId: 1,
        roomId: 1,
        confirmedCursor: null,
        hasOlder: false,
      ),
      103,
    );
  });

  test('D: huecos de ID acreditados avanzan al último', () {
    expect(
      computeSafeReadFrontier(
        timeline: others([101, 104, 109, 115]),
        presentedIds: {101, 104, 109, 115},
        userId: 1,
        roomId: 1,
        confirmedCursor: null,
        hasOlder: false,
      ),
      115,
    );
  });

  test('E: historial paginado sin cursor no infiere el inicio', () {
    expect(
      computeSafeReadFrontier(
        timeline: others([109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120]),
        presentedIds: {109, 110, 111, 112, 113, 114, 115, 116, 117, 118, 119, 120},
        userId: 1,
        roomId: 1,
        confirmedCursor: null,
        hasOlder: true,
      ),
      isNull,
    );
  });

  test('F: no exige presentar mensajes propios', () {
    final timeline = [
      ChatMessage.fromJson(sampleMessageJson(id: 101, senderId: 2)),
      ChatMessage.fromJson(sampleMessageJson(id: 102, senderId: 1, body: 'propio')),
      ChatMessage.fromJson(sampleMessageJson(id: 103, senderId: 2)),
    ];
    expect(
      computeSafeReadFrontier(
        timeline: timeline,
        presentedIds: {101, 103},
        userId: 1,
        roomId: 1,
        confirmedCursor: null,
        hasOlder: false,
      ),
      103,
    );
  });

  test('G: hidden y deleted no bloquean ni adelantan indebidamente', () {
    final timeline = [
      ChatMessage.fromJson(sampleMessageJson(id: 101, senderId: 2)),
      ChatMessage.fromJson(sampleMessageJson(id: 102, senderId: 2, status: 'hidden')),
      ChatMessage.fromJson(
        sampleMessageJson(id: 103, senderId: 1, status: 'deleted_by_sender'),
      ),
      ChatMessage.fromJson(sampleMessageJson(id: 104, senderId: 2)),
    ];
    expect(
      computeSafeReadFrontier(
        timeline: timeline,
        presentedIds: {104},
        userId: 1,
        roomId: 1,
        confirmedCursor: null,
        hasOlder: false,
      ),
      isNull,
    );
    expect(
      computeSafeReadFrontier(
        timeline: timeline,
        presentedIds: {101, 104},
        userId: 1,
        roomId: 1,
        confirmedCursor: null,
        hasOlder: false,
      ),
      104,
    );
  });

  test('cursor confirmado permite continuar sin recargar el pasado', () {
    expect(
      computeSafeReadFrontier(
        timeline: others([109, 110, 111]),
        presentedIds: {110, 111},
        userId: 1,
        roomId: 1,
        confirmedCursor: 109,
        hasOlder: true,
      ),
      111,
    );
  });

  test('trustedMaxId no atraviesa cola no contigua', () {
    expect(
      computeSafeReadFrontier(
        timeline: others([101, 102, 150]),
        presentedIds: {101, 102, 150},
        userId: 1,
        roomId: 1,
        confirmedCursor: null,
        hasOlder: false,
        trustedMaxId: 102,
      ),
      102,
    );
  });
}
