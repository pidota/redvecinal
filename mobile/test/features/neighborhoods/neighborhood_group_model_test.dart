import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/neighborhoods/data/models/neighborhood_group.dart';

import 'neighborhood_test_support.dart';

void main() {
  group('NeighborhoodGroup.fromJson', () {
    test('parsea junta con municipio anidado', () {
      final group = NeighborhoodGroup.fromJson(sampleGroupJson());

      expect(group.id, 1);
      expect(group.municipality?.name, 'Chépica');
      expect(group.municipalityLabel, 'Chépica');
    });

    test('sin clave municipality deja municipality nulo', () {
      final group = NeighborhoodGroup.fromJson(sampleGroupJson(includeMunicipality: false));

      expect(group.municipality, isNull);
      expect(group.municipalityLabel, 'Municipio #10');
    });

    test('junta suspendida conserva status', () {
      final group = NeighborhoodGroup.fromJson(sampleGroupJson(status: 'suspended'));

      expect(group.status, 'suspended');
    });
  });
}
