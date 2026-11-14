import 'post_comment.dart';

class PaginatedPostComments {
  const PaginatedPostComments({
    required this.items,
    required this.currentPage,
    required this.lastPage,
  });

  final List<PostComment> items;
  final int currentPage;
  final int lastPage;

  bool get hasMore => currentPage < lastPage;

  PaginatedPostComments append(PaginatedPostComments next) {
    final seen = {for (final comment in items) comment.id};
    final merged = [
      ...items,
      ...next.items.where((comment) => seen.add(comment.id)),
    ];

    return PaginatedPostComments(
      items: merged,
      currentPage: next.currentPage,
      lastPage: next.lastPage,
    );
  }

  PaginatedPostComments withAppendedComment(PostComment comment) {
    if (items.any((c) => c.id == comment.id)) {
      return this;
    }
    return PaginatedPostComments(
      items: [...items, comment],
      currentPage: currentPage,
      lastPage: lastPage,
    );
  }
}
