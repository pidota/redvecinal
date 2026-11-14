import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/posts/data/models/post_category.dart';

void main() {
  test('PostCategory parsea campos', () {
    final category = PostCategory.fromJson({
      'id': 2,
      'slug': 'aviso-comunitario',
      'name': 'Aviso comunitario',
      'description': 'Avisos',
      'default_audience': 'group',
      'sort_order': 1,
      'is_system': true,
    });

    expect(category.id, 2);
    expect(category.slug, 'aviso-comunitario');
    expect(category.defaultAudience, 'group');
  });
}
