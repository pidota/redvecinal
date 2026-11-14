import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';

import 'post_test_support.dart';

void main() {
  test('pending usa pending_content y no aparece como publicada', () {
    final detail = pendingPostDetail(
      id: 77,
      title: 'Título pendiente',
      body: 'Cuerpo en moderación',
    );
    expect(detail.status, 'pending');
    expect(detail.isPublished, isFalse);
    expect(detail.title, 'Título pendiente');
    expect(detail.bodyDisplay, 'Cuerpo en moderación');
  });

  test('published con has_pending_amendment mantiene contenido publicado', () {
    final json = Map<String, dynamic>.from(sampleCommunityPostJson(id: 5));
    json['has_pending_amendment'] = true;
    json['pending_content'] = {
      'revision_id': 99,
      'title': 'Enmienda',
      'body': 'Cambio',
      'body_html': '<p>Cambio</p>',
    };
    final detail = PostDetail.fromJson(json);
    expect(detail.isPublished, isTrue);
    expect(detail.title, 'Aviso de reunión');
    expect(detail.hasPendingAmendment, isTrue);
  });
}
