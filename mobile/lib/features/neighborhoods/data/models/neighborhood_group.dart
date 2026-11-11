import '../../../auth/data/models/municipality_membership.dart';

class NeighborhoodGroup {
  const NeighborhoodGroup({
    required this.id,
    required this.municipalityId,
    required this.name,
    required this.slug,
    required this.status,
    this.description,
    this.address,
    this.municipality,
  });

  factory NeighborhoodGroup.fromJson(Map<String, dynamic> json) {
    MunicipalitySummary? municipality;
    final rawMunicipality = json['municipality'];
    if (rawMunicipality is Map<String, dynamic>) {
      municipality = MunicipalitySummary.fromJson(rawMunicipality);
    }

    return NeighborhoodGroup(
      id: json['id'] as int,
      municipalityId: json['municipality_id'] as int,
      name: json['name'] as String,
      slug: json['slug'] as String,
      status: json['status'] as String,
      description: json['description'] as String?,
      address: json['address'] as String?,
      municipality: municipality,
    );
  }

  final int id;
  final int municipalityId;
  final String name;
  final String slug;
  final String status;
  final String? description;
  final String? address;
  final MunicipalitySummary? municipality;

  String get municipalityLabel =>
      municipality?.name ?? 'Municipio #$municipalityId';
}
