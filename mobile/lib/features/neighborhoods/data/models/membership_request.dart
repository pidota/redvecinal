import 'neighborhood_group.dart';

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
  });

  factory MembershipRequest.fromJson(Map<String, dynamic> json) {
    NeighborhoodGroup? group;
    final rawGroup = json['neighborhood_group'];
    if (rawGroup is Map<String, dynamic>) {
      group = NeighborhoodGroup.fromJson(rawGroup);
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

  bool get isPending => status == 'pending';

  String get groupName =>
      neighborhoodGroup?.name ?? 'Junta #$neighborhoodGroupId';

  String get municipalityLabel => neighborhoodGroup?.municipalityLabel ?? '';

  MembershipRequest copyWith({
    String? status,
    String? reviewNote,
    DateTime? cancelledAt,
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
