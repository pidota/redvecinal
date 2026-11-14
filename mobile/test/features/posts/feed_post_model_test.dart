import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/posts/data/models/feed_post.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';

import 'post_test_support.dart';

void main() {
  test('parsea publicación comunitaria', () {
    final post = FeedPost.fromJson(sampleCommunityPostJson());
    expect(post.postKind, 'community');
    expect(post.neighborhoodGroup?.name, 'Junta Centro');
    expect(post.category?.slug, 'aviso-comunitario');
    expect(post.engagement.myReactionType, 'like');
    expect(post.attachments, hasLength(1));
    expect(post.title, 'Aviso de reunión');
  });

  test('parsea publicación municipal con junta nula', () {
    final post = FeedPost.fromJson(sampleMunicipalPostJson());
    expect(post.isMunicipal, isTrue);
    expect(post.neighborhoodGroup, isNull);
    expect(post.scopeLabel, 'Chépica');
    expect(post.engagement.myReactionType, isNull);
  });

  test('excerpt usa texto plano seguro', () {
    final excerpt = FeedPost.excerptFromBody('  Línea 1\n\nLínea 2  ');
    expect(excerpt, 'Línea 1 Línea 2');
  });

  test('paginated append evita duplicados', () {
    const first = PaginatedFeedPosts(items: [], currentPage: 1, lastPage: 2);
    final post = sampleCommunityPost();
    final merged = first.append(
      PaginatedFeedPosts(items: [post, post], currentPage: 2, lastPage: 2),
    );
    expect(merged.items, hasLength(1));
  });
}
