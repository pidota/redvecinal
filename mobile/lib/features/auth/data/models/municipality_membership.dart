class MunicipalitySummary {
  const MunicipalitySummary({
    required this.id,
    required this.name,
    required this.slug,
  });

  factory MunicipalitySummary.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      throw const FormatException('municipality nulo');
    }
    return MunicipalitySummary(
      id: json['id'] as int,
      name: json['name'] as String,
      slug: json['slug'] as String,
    );
  }

  final int id;
  final String name;
  final String slug;
}

class MunicipalityMembership {
  const MunicipalityMembership({
    required this.id,
    required this.municipalityId,
    required this.municipality,
    required this.role,
    required this.status,
  });

  factory MunicipalityMembership.fromJson(Map<String, dynamic> json) {
    return MunicipalityMembership(
      id: json['id'] as int,
      municipalityId: json['municipality_id'] as int,
      municipality: MunicipalitySummary.fromJson(json['municipality'] as Map<String, dynamic>?),
      role: json['role'] as String,
      status: json['status'] as String,
    );
  }

  final int id;
  final int municipalityId;
  final MunicipalitySummary municipality;
  final String role;
  final String status;
}
