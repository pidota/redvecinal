import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/features/auth/data/models/auth_user.dart';

void main() {
  test('parsea usuario sin wrapper data y varias municipalidades', () {
    final user = AuthUser.fromJson({
      'id': 5,
      'name': 'Ana',
      'email': 'ana@test.com',
      'municipality_memberships': [
        {
          'id': 1,
          'municipality_id': 10,
          'municipality': {'id': 10, 'name': 'A', 'slug': 'a'},
          'role': 'funcionario',
          'status': 'active',
        },
        {
          'id': 2,
          'municipality_id': 20,
          'municipality': {'id': 20, 'name': 'B', 'slug': 'b'},
          'role': 'administrador',
          'status': 'active',
        },
      ],
    });

    expect(user.municipalityMemberships, hasLength(2));
    expect(user.municipalityMemberships.first.municipality.slug, 'a');
  });
}
