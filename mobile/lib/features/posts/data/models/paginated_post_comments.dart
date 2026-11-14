import 'post_comment.dart';

/// Orden ascendente por `createdAt`; empate estable por `id`.
int comparePostCommentsChronologically(PostComment a, PostComment b) {
  final aDate = a.createdAt;
  final bDate = b.createdAt;
  if (aDate != null && bDate != null) {
    final byDate = aDate.compareTo(bDate);
    if (byDate != 0) {
      return byDate;
    }
  } else if (aDate != null) {
    return -1;
  } else if (bDate != null) {
    return 1;
  }
  return a.id.compareTo(b.id);
}

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

  /// Lista fusionada sin duplicados, en orden cronológico ascendente.
  PaginatedPostComments withOrderedItems(List<PostComment> ordered) {
    return PaginatedPostComments(
      items: ordered,
      currentPage: currentPage,
      lastPage: lastPage,
    );
  }

  PaginatedPostComments sortedChronologically() {
    final next = [...items]..sort(comparePostCommentsChronologically);
    return PaginatedPostComments(
      items: next,
      currentPage: currentPage,
      lastPage: lastPage,
    );
  }

  PaginatedPostComments append(PaginatedPostComments next) {
    final seen = {for (final comment in items) comment.id};
    final merged = [
      ...items,
      ...next.items.where((comment) => seen.add(comment.id)),
    ];
    merged.sort(comparePostCommentsChronologically);

    return PaginatedPostComments(
      items: merged,
      currentPage: next.currentPage,
      lastPage: next.lastPage,
    );
  }

  PaginatedPostComments withAppendedComment(PostComment comment) {
    if (items.any((c) => c.id == comment.id)) {
      return sortedChronologically();
    }
    final merged = [...items, comment]
      ..sort(comparePostCommentsChronologically);
    return PaginatedPostComments(
      items: merged,
      currentPage: currentPage,
      lastPage: lastPage,
    );
  }
}
