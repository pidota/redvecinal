import 'municipality_membership.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.email,
    required this.municipalityMemberships,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    final raw = json['municipality_memberships'];
    final list = raw is List<dynamic> ? raw : <dynamic>[];

    return AuthUser(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
      municipalityMemberships: list
          .map((e) => MunicipalityMembership.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final int id;
  final String name;
  final String email;
  final List<MunicipalityMembership> municipalityMemberships;
}
