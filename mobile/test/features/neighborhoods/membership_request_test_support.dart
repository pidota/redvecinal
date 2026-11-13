import 'package:red_vecinal/features/neighborhoods/data/membership_request_repository.dart';
import 'package:red_vecinal/features/neighborhoods/data/models/membership_request.dart';
import 'package:red_vecinal/features/neighborhoods/data/models/paginated_membership_requests.dart';
import 'package:red_vecinal/features/neighborhoods/data/models/paginated_neighborhood_groups.dart';
import 'package:red_vecinal/features/neighborhoods/data/models/neighborhood_group.dart';

import 'neighborhood_test_support.dart';

Map<String, dynamic> sampleMembershipRequestJson({
  int id = 100,
  int groupId = 1,
  String status = 'pending',
  String? requestNote,
  bool includeGroup = true,
  bool includeRequester = false,
  String requesterName = 'Vecino solicitante',
}) {
  return {
    'id': id,
    'status': status,
    'neighborhood_group_id': groupId,
    'request_note': requestNote,
    'review_note': null,
    'reviewed_at': null,
    'rejected_at': null,
    'cancelled_at': null,
    'created_at': '2026-01-15T10:00:00.000000Z',
    if (includeGroup) 'neighborhood_group': sampleGroupJson(id: groupId),
    if (includeRequester) 'requester': {'id': 900, 'name': requesterName},
  };
}

class FakeMembershipRequestGateway implements MembershipRequestGateway {
  FakeMembershipRequestGateway({
    NeighborhoodGroup? contextGroup,
    this.contextFailure,
    this.submitResult,
    this.submitFailure,
    this.myRequestsPage,
    this.myRequestsPagesByNumber,
    this.myRequestsFailure,
    this.myRequestsFailurePage,
    this.myRequestsDelayMs = 0,
    this.contextDelayMs = 0,
    this.submitDelayMs = 0,
    this.cancelFailure,
    this.submitCallCount = 0,
    this.myRequestsCallCount = 0,
    this.myRequestsPagesByGroup,
    this.lastMyRequestsGroupId,
    this.reviewableGroupsPage,
    this.reviewableGroupsPagesByNumber,
    this.reviewableGroupsFailure,
    this.groupRequestsPagesByNumber,
    this.groupRequestsFailure,
    this.approveFailure,
    this.rejectFailure,
    this.approveDelayMs = 0,
    this.rejectDelayMs = 0,
    this.approveCallCount = 0,
    this.rejectCallCount = 0,
  }) : contextGroup = contextGroup ?? sampleNeighborhoodGroup();

  NeighborhoodGroup? contextGroup;
  Object? contextFailure;
  MembershipRequest? submitResult;
  Object? submitFailure;
  PaginatedMembershipRequests? myRequestsPage;
  Map<int, PaginatedMembershipRequests>? myRequestsPagesByNumber;
  Object? myRequestsFailure;
  int? myRequestsFailurePage;
  int myRequestsDelayMs;
  int contextDelayMs;
  int submitDelayMs;
  Object? cancelFailure;
  int submitCallCount;
  int myRequestsCallCount;
  Map<String, PaginatedMembershipRequests>? myRequestsPagesByGroup;
  int? lastMyRequestsGroupId;
  PaginatedNeighborhoodGroups? reviewableGroupsPage;
  Map<int, PaginatedNeighborhoodGroups>? reviewableGroupsPagesByNumber;
  Object? reviewableGroupsFailure;
  Map<String, PaginatedMembershipRequests>? groupRequestsPagesByNumber;
  Object? groupRequestsFailure;
  Object? approveFailure;
  Object? rejectFailure;
  int approveDelayMs;
  int rejectDelayMs;
  int approveCallCount;
  int rejectCallCount;
  int reviewableGroupsCallCount = 0;

  @override
  Future<void> cancel(int requestId) async {
    if (cancelFailure != null) {
      throw cancelFailure!;
    }
  }

  @override
  Future<NeighborhoodGroup> membershipContext(int groupId) async {
    if (contextDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: contextDelayMs));
    }
    if (contextFailure != null) {
      throw contextFailure!;
    }
    return contextGroup ?? sampleNeighborhoodGroup(id: groupId);
  }

  @override
  Future<PaginatedMembershipRequests> myRequests({int page = 1, int? neighborhoodGroupId}) async {
    myRequestsCallCount++;
    lastMyRequestsGroupId = neighborhoodGroupId;
    if (myRequestsDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: myRequestsDelayMs));
    }
    if (myRequestsFailure != null &&
        (myRequestsFailurePage == null || myRequestsFailurePage == page)) {
      throw myRequestsFailure!;
    }

    if (neighborhoodGroupId != null) {
      final byGroup = myRequestsPagesByGroup;
      final groupKey = '$neighborhoodGroupId|$page';
      if (byGroup != null && byGroup.containsKey(groupKey)) {
        return byGroup[groupKey]!;
      }
    }

    PaginatedMembershipRequests resolved;
    final byPage = myRequestsPagesByNumber;
    if (byPage != null && byPage.containsKey(page)) {
      resolved = byPage[page]!;
    } else {
      resolved = myRequestsPage ??
          PaginatedMembershipRequests(
            items: [
              MembershipRequest.fromJson(sampleMembershipRequestJson()),
            ],
            currentPage: page,
            lastPage: 1,
          );
    }

    if (neighborhoodGroupId == null) {
      return resolved;
    }

    final filtered = resolved.items
        .where((request) => request.neighborhoodGroupId == neighborhoodGroupId)
        .toList(growable: false);

    return PaginatedMembershipRequests(
      items: filtered,
      currentPage: resolved.currentPage,
      lastPage: resolved.lastPage,
    );
  }

  @override
  Future<PaginatedNeighborhoodGroups> reviewableGroups({int page = 1}) async {
    reviewableGroupsCallCount++;
    if (reviewableGroupsFailure != null) {
      throw reviewableGroupsFailure!;
    }
    final byPage = reviewableGroupsPagesByNumber;
    if (byPage != null && byPage.containsKey(page)) {
      return byPage[page]!;
    }
    return reviewableGroupsPage ??
        PaginatedNeighborhoodGroups(
          items: [sampleNeighborhoodGroup()],
          currentPage: page,
          lastPage: 1,
        );
  }

  @override
  Future<PaginatedMembershipRequests> groupRequests({
    required int groupId,
    required String status,
    int page = 1,
  }) async {
    if (groupRequestsFailure != null) {
      throw groupRequestsFailure!;
    }
    final key = '$groupId|$status|$page';
    final map = groupRequestsPagesByNumber;
    if (map != null && map.containsKey(key)) {
      return map[key]!;
    }
    return PaginatedMembershipRequests(
      items: [
        MembershipRequest.fromJson(
          sampleMembershipRequestJson(groupId: groupId, includeRequester: true),
        ),
      ],
      currentPage: page,
      lastPage: 1,
    );
  }

  @override
  Future<MembershipRequest> approve(int requestId, {String? reviewNote}) async {
    approveCallCount++;
    if (approveDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: approveDelayMs));
    }
    if (approveFailure != null) {
      throw approveFailure!;
    }
    return MembershipRequest.fromJson(
      sampleMembershipRequestJson(id: requestId, status: 'approved', requestNote: reviewNote),
    );
  }

  @override
  Future<MembershipRequest> reject(int requestId, {String? reviewNote}) async {
    rejectCallCount++;
    if (rejectDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: rejectDelayMs));
    }
    if (rejectFailure != null) {
      throw rejectFailure!;
    }
    return MembershipRequest.fromJson(
      sampleMembershipRequestJson(id: requestId, status: 'rejected', requestNote: reviewNote),
    );
  }

  @override
  Future<MembershipRequest> submit({required int groupId, String? requestNote}) async {
    submitCallCount++;
    if (submitDelayMs > 0) {
      await Future<void>.delayed(Duration(milliseconds: submitDelayMs));
    }
    if (submitFailure != null) {
      throw submitFailure!;
    }
    return submitResult ??
        MembershipRequest.fromJson(
          sampleMembershipRequestJson(groupId: groupId, requestNote: requestNote),
        );
  }
}
