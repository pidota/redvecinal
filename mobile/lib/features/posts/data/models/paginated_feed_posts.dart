import 'feed_post.dart';

class PaginatedFeedPosts {
  const PaginatedFeedPosts({
    required this.items,
    required this.currentPage,
    required this.lastPage,
  });

  final List<FeedPost> items;
  final int currentPage;
  final int lastPage;

  bool get hasMore => currentPage < lastPage;

  PaginatedFeedPosts append(PaginatedFeedPosts next) {
    final seen = {for (final post in items) post.id};
    final merged = [...items, ...next.items.where((post) => seen.add(post.id))];

    return PaginatedFeedPosts(
      items: merged,
      currentPage: next.currentPage,
      lastPage: next.lastPage,
    );
  }
}
