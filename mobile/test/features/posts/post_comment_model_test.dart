import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_post_comments.dart';
import 'package:red_vecinal/features/posts/data/models/post_comment.dart';

import 'post_test_support.dart';

void main() {
  test('PostComment parsea autor y campos principales', () {
    final comment = PostComment.fromJson(sampleCommentJson());
    expect(comment.id, 100);
    expect(comment.postId, 1);
    expect(comment.author?.name, 'Pedro Vecino');
    expect(comment.authorDisplayName, 'Pedro Vecino');
    expect(comment.plainBody, 'Gracias por el aviso.');
    expect(comment.createdAt, isNotNull);
  });

  test('PostComment tolera autor ausente y campos extra', () {
    final json = Map<String, dynamic>.from(sampleCommentJson());
    json.remove('author');
    json['extra'] = 'ignored';
    final comment = PostComment.fromJson(json);
    expect(comment.author, isNull);
    expect(comment.authorDisplayName, 'Vecino');
  });

  test('append ordena cronológicamente tras fusión desordenada', () {
    final first = PaginatedPostComments(
      items: [
        sampleCommentChronological(id: 1, createdAt: '2026-11-14T10:00:00Z'),
        sampleCommentChronological(id: 15, createdAt: '2026-11-14T10:14:00Z'),
        sampleCommentChronological(id: 100, createdAt: '2026-11-14T10:30:00Z'),
      ],
      currentPage: 1,
      lastPage: 2,
    );
    final second = PaginatedPostComments(
      items: [
        sampleCommentChronological(id: 16, createdAt: '2026-11-14T10:15:00Z'),
        sampleCommentChronological(id: 17, createdAt: '2026-11-14T10:16:00Z'),
      ],
      currentPage: 2,
      lastPage: 2,
    );
    final merged = first.append(second);
    expect(merged.items.map((c) => c.id), [1, 15, 16, 17, 100]);
  });

  test('PaginatedPostComments deduplica en append', () {
    final first = sampleCommentsPage(
      items: [sampleComment(id: 1), sampleComment(id: 2)],
      lastPage: 2,
    );
    final second = PaginatedPostComments(
      items: [sampleComment(id: 2), sampleComment(id: 3)],
      currentPage: 2,
      lastPage: 2,
    );
    final merged = first.append(second);
    expect(merged.items.map((c) => c.id), [1, 2, 3]);
    expect(merged.hasMore, isFalse);
  });

  test('withAppendedComment no duplica por id', () {
    final page = sampleCommentsPage(items: [sampleComment(id: 5)]);
    final updated = page.withAppendedComment(sampleComment(id: 5));
    expect(updated.items.length, 1);
    final added = page.withAppendedComment(sampleComment(id: 6));
    expect(added.items.length, 2);
  });
}
