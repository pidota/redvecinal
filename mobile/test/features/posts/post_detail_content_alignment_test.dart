import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/posts/data/models/feed_post.dart';
import 'package:red_vecinal/features/posts/data/models/feed_post_mine_presentation.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';

import 'post_test_support.dart';

void main() {
  test('A rejected prioriza working_content sobre content', () {
    final json = {
      ...sampleCommunityPostJson(
        id: 60,
        title: 'Título publicado viejo',
        body: 'Cuerpo publicado viejo',
      ),
      'status': 'rejected',
      'working_content': {
        'revision_id': 601,
        'title': 'Corrección rechazada',
        'body': 'Texto rechazado',
      },
    };
    final detail = PostDetail.fromJson(json);
    final listPost = FeedPost.fromJson(json);

    expect(
      FeedPostMinePresentation.listTitle(listPost),
      'Corrección rechazada',
    );
    expect(detail.title, 'Corrección rechazada');
    expect(detail.bodyDisplay, 'Texto rechazado');
    expect(detail.bodyDisplay, isNot(contains('publicado viejo')));
  });

  test('B rejected título y cuerpo de la misma revisión working', () {
    final json = {
      'id': 61,
      'post_kind': 'community',
      'status': 'rejected',
      'comments_enabled': true,
      'published_at': null,
      'has_pending_amendment': false,
      'author': {'id': 1, 'name': 'A'},
      'neighborhood_group': {'id': 2, 'name': 'G', 'slug': 'g'},
      'category': {'id': 2, 'slug': 'x', 'name': 'X'},
      'municipality': {'id': 1, 'name': 'M', 'slug': 'm'},
      'content': {
        'revision_id': 1,
        'title': 'No usar',
        'body': 'No usar cuerpo',
        'body_html': '<p>No</p>',
      },
      'working_content': {
        'revision_id': 2,
        'title': 'Par rechazado',
        'body': 'Cuerpo pareado',
      },
      'engagement': {
        'comments_count': 0,
        'reactions_count': 0,
        'my_reaction': null,
      },
      'attachments': [],
    };
    final detail = PostDetail.fromJson(json);
    expect(detail.title, 'Par rechazado');
    expect(detail.bodyDisplay, 'Cuerpo pareado');
  });

  test('C draft usa working_content como bloque cuando existe', () {
    final json = {
      ...mineDraftPostJson(id: 62, title: 'Borrador', body: 'Cuerpo borrador'),
      'content': {
        'revision_id': 99,
        'title': 'Contenido ajeno',
        'body': 'No debe mezclarse',
      },
    };
    final detail = PostDetail.fromJson(json);
    expect(detail.title, 'Borrador');
    expect(detail.bodyDisplay, 'Cuerpo borrador');
  });

  test('D pending usa pending_content', () {
    final detail = pendingPostDetail(
      id: 63,
      title: 'En revisión',
      body: 'Solo pendiente',
    );
    expect(detail.title, 'En revisión');
    expect(detail.bodyDisplay, 'Solo pendiente');
  });

  test('E published con enmienda mantiene contenido publicado', () {
    final json = Map<String, dynamic>.from(
      sampleCommunityPostJson(id: 64, title: 'Live', body: 'Cuerpo live'),
    );
    json['has_pending_amendment'] = true;
    json['working_content'] = {
      'revision_id': 8,
      'title': 'Enmienda',
      'body': 'No visible como publicado',
    };
    json['pending_content'] = {
      'revision_id': 9,
      'title': 'Pending title',
      'body': 'Pending body',
      'body_html': '<p>Pending body</p>',
    };
    final detail = PostDetail.fromJson(json);
    final listPost = FeedPost.fromJson(json);

    expect(detail.isPublished, isTrue);
    expect(detail.title, 'Live');
    expect(detail.bodyDisplay, 'Cuerpo live');
    expect(FeedPostMinePresentation.listTitle(listPost), 'Live');
    expect(detail.bodyDisplay, isNot(contains('Pending body')));
  });
}
