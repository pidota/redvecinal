import 'membership_request.dart';

class PaginatedMembershipRequests {
  const PaginatedMembershipRequests({
    required this.items,
    required this.currentPage,
    required this.lastPage,
  });

  final List<MembershipRequest> items;
  final int currentPage;
  final int lastPage;

  bool get hasMore => currentPage < lastPage;

  PaginatedMembershipRequests append(PaginatedMembershipRequests next) {
    final seen = {for (final item in items) item.id};
    final merged = [
      ...items,
      ...next.items.where((item) => seen.add(item.id)),
    ];

    return PaginatedMembershipRequests(
      items: merged,
      currentPage: next.currentPage,
      lastPage: next.lastPage,
    );
  }
}
