import 'package:red_vecinal/features/auth/data/models/municipality_membership.dart';
import 'package:red_vecinal/features/neighborhoods/data/models/neighborhood_group.dart';
import 'package:red_vecinal/features/neighborhoods/data/neighborhood_repository.dart';

NeighborhoodGroup sampleNeighborhoodGroup({
  int id = 1,
  String status = 'active',
  MunicipalitySummary? municipality,
  String? description,
}) {
  return NeighborhoodGroup(
    id: id,
    municipalityId: municipality?.id ?? 10,
    name: 'Junta Centro',
    slug: 'junta-centro',
    status: status,
    description: description ?? 'Descripción breve',
    municipality: municipality ??
        const MunicipalitySummary(id: 10, name: 'Chépica', slug: 'chepica'),
  );
}

Map<String, dynamic> sampleGroupJson({
  int id = 1,
  String status = 'active',
  bool includeMunicipality = true,
  String? description,
}) {
  return {
    'id': id,
    'municipality_id': 10,
    'name': 'Junta Centro',
    'slug': 'junta-centro',
    'description': description ?? 'Descripción breve',
    'address': null,
    'status': status,
    if (includeMunicipality)
      'municipality': {
        'id': 10,
        'name': 'Chépica',
        'slug': 'chepica',
      },
  };
}

class FakeNeighborhoodGateway implements NeighborhoodGateway {
  FakeNeighborhoodGateway({
    this.groups = const [],
    this.failure,
    this.callCount = 0,
  });

  List<NeighborhoodGroup> groups;
  Object? failure;
  int callCount;

  @override
  Future<List<NeighborhoodGroup>> myGroups() async {
    callCount++;
    if (failure != null) {
      throw failure!;
    }
    return groups;
  }
}
