import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/neighborhoods/data/models/neighborhood_group.dart';

import 'neighborhood_test_support.dart';

/// Espeja la forma documentada en `MobileGroupsApiTest` y `NeighborhoodGroupResource`.
void main() {
  test('contrato junta en listado/show', () {
    final json = sampleGroupJson();
    final group = NeighborhoodGroup.fromJson(json);

    expect(group.id, 1);
    expect(group.municipalityId, 10);
    expect(group.name, 'Junta Centro');
    expect(group.slug, 'junta-centro');
    expect(group.status, 'active');
    expect(group.municipality?.slug, 'chepica');
    expect(json.containsKey('contact_email'), isFalse);
  });

  test('meta paginado Laravel en forma esperada por el repositorio', () {
    const payload = {
      'data': [
        {
          'id': 1,
          'municipality_id': 10,
          'name': 'Junta Centro',
          'slug': 'junta-centro',
          'description': null,
          'address': null,
          'status': 'active',
          'municipality': {'id': 10, 'name': 'Chépica', 'slug': 'chepica'},
        },
      ],
      'links': {
        'first': 'http://test/api/v1/groups?page=1',
        'last': 'http://test/api/v1/groups?page=2',
        'prev': null,
        'next': 'http://test/api/v1/groups?page=2',
      },
      'meta': {
        'current_page': 1,
        'last_page': 2,
        'per_page': 15,
        'total': 20,
      },
    };

    final data = payload['data'] as List<dynamic>;
    final meta = payload['meta'] as Map<String, dynamic>;
    final parsed = data.whereType<Map<String, dynamic>>().map(NeighborhoodGroup.fromJson).toList();

    expect(parsed, hasLength(1));
    expect(meta['current_page'], 1);
    expect(meta['last_page'], 2);
    expect(parsed.first.municipality?.name, 'Chépica');
  });
}
