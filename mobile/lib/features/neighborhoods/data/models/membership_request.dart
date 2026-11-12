import 'neighborhood_group.dart';

class MembershipRequester {
  const MembershipRequester({required this.id, required this.name});

  factory MembershipRequester.fromJson(Map<String, dynamic> json) {
    return MembershipRequester(
      id: json['id'] as int,
      name: json['name'] as String,
    );
  }

  final int id;
  final String name;
}

class MembershipRequest {
  const MembershipRequest({
    required this.id,
    required this.status,
    required this.neighborhoodGroupId,
    this.requestNote,
    this.reviewNote,
    this.createdAt,
    this.reviewedAt,
    this.rejectedAt,
    this.cancelledAt,
    this.neighborhoodGroup,
    this.requester,
  });

  factory MembershipRequest.fromJson(Map<String, dynamic> json) {
    NeighborhoodGroup? group;
    final rawGroup = json['neighborhood_group'];
    if (rawGroup is Map<String, dynamic>) {
      group = NeighborhoodGroup.fromJson(rawGroup);
    }

    MembershipRequester? requester;
    final rawRequester = json['requester'];
    if (rawRequester is Map<String, dynamic>) {
      requester = MembershipRequester.fromJson(rawRequester);
    }

    return MembershipRequest(
      id: json['id'] as int,
      status: json['status'] as String,
      neighborhoodGroupId: json['neighborhood_group_id'] as int,
      requestNote: json['request_note'] as String?,
      reviewNote: json['review_note'] as String?,
      createdAt: _parseDate(json['created_at']),
      reviewedAt: _parseDate(json['reviewed_at']),
      rejectedAt: _parseDate(json['rejected_at']),
      cancelledAt: _parseDate(json['cancelled_at']),
      neighborhoodGroup: group,
      requester: requester,
    );
  }

  final int id;
  final String status;
  final int neighborhoodGroupId;
  final String? requestNote;
  final String? reviewNote;
  final DateTime? createdAt;
  final DateTime? reviewedAt;
  final DateTime? rejectedAt;
  final DateTime? cancelledAt;
  final NeighborhoodGroup? neighborhoodGroup;
  final MembershipRequester? requester;

  bool get isPending => status == 'pending';

  String get groupName =>
      neighborhoodGroup?.name ?? 'Junta #$neighborhoodGroupId';

  String get municipalityLabel => neighborhoodGroup?.municipalityLabel ?? '';

  String get requesterDisplayName => requester?.name ?? 'Vecino';

  MembershipRequest copyWith({
    String? status,
    String? reviewNote,
    DateTime? cancelledAt,
    MembershipRequester? requester,
  }) {
    return MembershipRequest(
      id: id,
      status: status ?? this.status,
      neighborhoodGroupId: neighborhoodGroupId,
      requestNote: requestNote,
      reviewNote: reviewNote ?? this.reviewNote,
      createdAt: createdAt,
      reviewedAt: reviewedAt,
      rejectedAt: rejectedAt,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      neighborhoodGroup: neighborhoodGroup,
      requester: requester ?? this.requester,
    );
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is! String || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }
}

String membershipRequestStatusLabel(String status) {
  return switch (status) {
    'pending' => 'Pendiente de revisión',
    'approved' => 'Aprobada',
    'rejected' => 'Rechazada',
    'cancelled' => 'Cancelada',
    _ => status,
  };
}

String membershipRequestStatusUserMessage(String status) {
  return switch (status) {
    'pending' => 'Tu solicitud está pendiente de revisión',
    'approved' => 'Tu incorporación fue aprobada',
    'rejected' => 'Tu solicitud fue rechazada',
    'cancelled' => 'Cancelaste esta solicitud',
    _ => membershipRequestStatusLabel(status),
  };
}
