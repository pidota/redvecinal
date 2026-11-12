import 'neighborhood_group.dart';

class PaginatedNeighborhoodGroups {
  const PaginatedNeighborhoodGroups({
    required this.items,
    required this.currentPage,
    required this.lastPage,
  });

  final List<NeighborhoodGroup> items;
  final int currentPage;
  final int lastPage;

  bool get hasMore => currentPage < lastPage;

  PaginatedNeighborhoodGroups append(PaginatedNeighborhoodGroups next) {
    final seen = {for (final group in items) group.id};
    final merged = [
      ...items,
      ...next.items.where((group) => seen.add(group.id)),
    ];

    return PaginatedNeighborhoodGroups(
      items: merged,
      currentPage: next.currentPage,
      lastPage: next.lastPage,
    );
  }
}
