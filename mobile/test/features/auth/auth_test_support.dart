import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/features/auth/data/models/auth_user.dart';
import 'package:red_vecinal/features/auth/data/models/login_response.dart';
import 'package:red_vecinal/features/auth/data/models/municipality_membership.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';

const testAppConfig = AppConfig(
  appName: 'Red Vecinal',
  environment: 'development',
  apiBaseUrl: 'http://test.api/v1',
);

AuthUser sampleAuthUser({
  int id = 1,
  String email = 'vecino@test.com',
  List<MunicipalityMembership>? memberships,
}) {
  return AuthUser(
    id: id,
    name: 'Vecino Test',
    email: email,
    municipalityMemberships: memberships ??
        [
          MunicipalityMembership(
            id: 1,
            municipalityId: 10,
            municipality: const MunicipalitySummary(id: 10, name: 'Chépica', slug: 'chepica'),
            role: 'funcionario',
            status: 'active',
          ),
        ],
  );
}

LoginResponse sampleLoginResponse() {
  return LoginResponse(
    token: '1|test-token',
    tokenType: 'Bearer',
    user: sampleAuthUser(),
  );
}

class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({
    this.loginResponse,
    this.meUser,
    this.loginFailure,
    this.meFailure,
    this.logoutFailure,
    this.logoutCalls = 0,
    this.loginCalls = 0,
  });

  LoginResponse? loginResponse;
  AuthUser? meUser;
  Object? loginFailure;
  Object? meFailure;
  Object? logoutFailure;
  int logoutCalls;
  int loginCalls;

  @override
  Future<LoginResponse> login({required String email, required String password}) async {
    loginCalls++;
    if (loginFailure != null) {
      throw loginFailure!;
    }
    return loginResponse ?? sampleLoginResponse();
  }

  @override
  Future<AuthUser> me() async {
    if (meFailure != null) {
      throw meFailure!;
    }
    return meUser ?? sampleAuthUser();
  }

  @override
  Future<void> logout() async {
    logoutCalls++;
    if (logoutFailure != null) {
      throw logoutFailure!;
    }
  }
}
