import 'post_moderation_review.dart';

/// Vista de cola de moderación: solo entradas revisables y conteo de omitidas.
class PaginatedPendingQueue {
  const PaginatedPendingQueue({
    required this.reviewableItems,
    required this.skippedItemCount,
    required this.currentPage,
    required this.lastPage,
  });

  static const empty = PaginatedPendingQueue(
    reviewableItems: [],
    skippedItemCount: 0,
    currentPage: 1,
    lastPage: 1,
  );

  final List<PostModerationReview> reviewableItems;
  final int skippedItemCount;
  final int currentPage;
  final int lastPage;

  bool get hasMore => currentPage < lastPage;

  bool get isTrulyEmpty => reviewableItems.isEmpty && skippedItemCount == 0;

  bool get hasOnlySkippedItems =>
      reviewableItems.isEmpty && skippedItemCount > 0;

  PaginatedPendingQueue append(PaginatedPendingQueue next) {
    final seen = {for (final r in reviewableItems) r.post.id};
    final merged = [
      ...reviewableItems,
      ...next.reviewableItems.where((r) => seen.add(r.post.id)),
    ];

    return PaginatedPendingQueue(
      reviewableItems: merged,
      skippedItemCount: skippedItemCount + next.skippedItemCount,
      currentPage: next.currentPage,
      lastPage: next.lastPage,
    );
  }
}
