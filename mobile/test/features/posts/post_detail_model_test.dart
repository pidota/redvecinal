import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';

import 'post_test_support.dart';

void main() {
  test('parseo detalle comunitario con adjuntos', () {
    final detail = sampleCommunityPostDetail();
    expect(detail.postKind, 'community');
    expect(detail.neighborhoodGroup?.name, 'Junta Centro');
    expect(detail.content?.body, contains('reunión'));
    expect(detail.attachments, hasLength(1));
    expect(
      detail.attachments.first.downloadUrl,
      contains('/posts/1/attachments/7'),
    );
    expect(
      detail.attachments.first.relativeDownloadPath,
      '/posts/1/attachments/7',
    );
  });

  test('parseo municipal con junta null', () {
    final detail = sampleMunicipalPostDetail();
    expect(detail.isMunicipal, isTrue);
    expect(detail.neighborhoodGroup, isNull);
    expect(detail.attachments, isEmpty);
  });

  test('texto de visualización prioriza body sobre html', () {
    final detail = PostDetail.fromJson(sampleCommunityPostJson());
    expect(detail.bodyDisplay, contains('reunión'));
    expect(detail.bodyDisplay, isNot(contains('<p>')));
  });

  test('fallback quita etiquetas html si no hay body', () {
    final json = sampleCommunityPostJson(body: '');
    json['content'] = {
      'revision_id': 1,
      'title': 'T',
      'body': '',
      'body_html': '<p>Solo HTML</p>',
    };
    final detail = PostDetail.fromJson(json);
    expect(detail.bodyDisplay, 'Solo HTML');
  });

  test('sanitiza nombre de archivo', () {
    expect(
      PostAttachment.sanitizeFileName('../evil.pdf'),
      isNot(contains('..')),
    );
  });
}
