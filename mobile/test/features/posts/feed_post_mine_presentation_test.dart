import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/posts/data/models/feed_post.dart';
import 'package:red_vecinal/features/posts/data/models/feed_post_mine_presentation.dart';

import 'post_test_support.dart';

void main() {
  test('A parser draft con working_content en listado propio', () {
    final post = FeedPost.fromJson(mineDraftPostJson());
    expect(FeedPostMinePresentation.listTitle(post), 'Borrador local');
    expect(post.title, 'Sin título');
    expect(post.workingContent?.title, 'Borrador local');
  });

  test('B parser pending con pending_content', () {
    final post = FeedPost.fromJson({
      ...mineDraftPostJson(id: 51),
      'status': 'pending',
      'working_content': null,
      'pending_content': {
        'revision_id': 12,
        'title': 'Propuesta enviada',
        'body': 'Texto pendiente',
      },
    });
    expect(FeedPostMinePresentation.listTitle(post), 'Propuesta enviada');
    expect(FeedPostMinePresentation.statusLabel('pending'), 'En revisión');
  });

  test('C parser rejected prioriza working_content', () {
    final post = FeedPost.fromJson({
      ...mineDraftPostJson(id: 52, title: 'Corregir'),
      'status': 'rejected',
    });
    expect(FeedPostMinePresentation.listTitle(post), 'Corregir');
  });

  test('D published con enmienda conserva título publicado', () {
    final post = FeedPost.fromJson({
      ...sampleCommunityPostJson(id: 53, title: 'Versión live'),
      'has_pending_amendment': true,
      'working_content': {
        'revision_id': 2,
        'title': 'Enmienda',
        'body': 'Nuevo',
      },
    });
    expect(FeedPostMinePresentation.listTitle(post), 'Versión live');
    expect(FeedPostMinePresentation.showsAmendmentHint(post), isTrue);
    expect(post.title, 'Versión live');
  });

  test('E hidden y archived usan content publicado disponible', () {
    final hidden = FeedPost.fromJson({
      ...sampleCommunityPostJson(id: 54, title: 'Oculta live'),
      'status': 'hidden',
    });
    expect(FeedPostMinePresentation.listTitle(hidden), 'Oculta live');

    final archived = FeedPost.fromJson({
      ...sampleCommunityPostJson(id: 55, title: 'Archivada live'),
      'status': 'archived',
    });
    expect(FeedPostMinePresentation.listTitle(archived), 'Archivada live');
  });

  test('Q feed público no usa working_content en title', () {
    final published = FeedPost.fromJson(sampleCommunityPostJson());
    expect(published.workingContent, isNull);
    expect(published.title, 'Aviso de reunión');

    final withWorking = FeedPost.fromJson({
      ...sampleCommunityPostJson(title: 'Público'),
      'working_content': {
        'revision_id': 9,
        'title': 'Privado',
        'body': 'secreto',
      },
    });
    expect(withWorking.title, 'Público');
    expect(withWorking.workingContent?.title, 'Privado');
  });
}
