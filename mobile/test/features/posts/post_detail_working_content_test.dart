import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';

void main() {
  test('parsea working_content sin romper content publicado', () {
    final json = {
      'id': 3,
      'post_kind': 'community',
      'status': 'draft',
      'comments_enabled': true,
      'published_at': null,
      'author': {'id': 1, 'name': 'A'},
      'neighborhood_group': {'id': 2, 'name': 'G', 'slug': 'g'},
      'category': {'id': 2, 'slug': 'x', 'name': 'X'},
      'municipality': {'id': 1, 'name': 'M', 'slug': 'm'},
      'content': null,
      'working_content': {
        'revision_id': 44,
        'title': 'Borrador',
        'body': 'Texto',
      },
      'engagement': {
        'comments_count': 0,
        'reactions_count': 0,
        'my_reaction': null,
      },
      'attachments': [],
    };
    final detail = PostDetail.fromJson(json);
    expect(detail.editableRevisionId, 44);
    expect(detail.title, 'Borrador');
    expect(detail.content, isNull);
  });
}
