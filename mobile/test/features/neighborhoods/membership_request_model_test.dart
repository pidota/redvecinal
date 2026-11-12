import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/neighborhoods/data/models/membership_request.dart';
import 'package:red_vecinal/features/neighborhoods/data/models/paginated_membership_requests.dart';

import 'membership_request_test_support.dart';

void main() {
  test('parsea requester para revisión', () {
    final request = MembershipRequest.fromJson(
      sampleMembershipRequestJson(includeRequester: true, requesterName: 'María López'),
    );
    expect(request.requester?.name, 'María López');
    expect(request.requesterDisplayName, 'María López');
  });

  test('parsea solicitud con junta anidada', () {
    final request = MembershipRequest.fromJson(sampleMembershipRequestJson());
    expect(request.id, 100);
    expect(request.status, 'pending');
    expect(request.neighborhoodGroupId, 1);
    expect(request.neighborhoodGroup?.name, 'Junta Centro');
    expect(request.isPending, isTrue);
  });

  test('etiquetas de estado en español', () {
    expect(membershipRequestStatusUserMessage('pending'), contains('pendiente'));
    expect(membershipRequestStatusUserMessage('approved'), contains('aprobada'));
  });

  test('paginated append dedupe por id', () {
    final first = MembershipRequest.fromJson(sampleMembershipRequestJson(id: 1));
    final dup = MembershipRequest.fromJson(sampleMembershipRequestJson(id: 1, status: 'approved'));
    final second = MembershipRequest.fromJson(sampleMembershipRequestJson(id: 2));

    final page = PaginatedMembershipRequests(
      items: [first],
      currentPage: 1,
      lastPage: 2,
    ).append(
      PaginatedMembershipRequests(
        items: [dup, second],
        currentPage: 2,
        lastPage: 2,
      ),
    );

    expect(page.items, hasLength(2));
    expect(page.items.map((r) => r.id), [1, 2]);
  });
}
