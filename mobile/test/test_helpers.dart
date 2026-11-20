import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/app.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/storage/token_storage.dart';
import 'package:red_vecinal/core/network/unauthorized_handler.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/auth/domain/auth_state.dart';

import 'features/auth/auth_test_support.dart';
import 'features/neighborhoods/neighborhood_test_support.dart';
import 'features/posts/post_test_support.dart';
import 'package:red_vecinal/features/neighborhoods/data/neighborhood_repository.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_feed_posts.dart';
import 'package:red_vecinal/features/posts/data/post_report_outcome_store.dart';
import 'package:red_vecinal/features/chat/data/chat_repository.dart';
import 'package:red_vecinal/features/chat/data/chat_uncertain_store.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';
import 'features/chat/chat_test_support.dart';

class AuthenticatedBootAuthController extends AuthController {
  @override
  AuthState build() => AuthAuthenticated(sampleAuthUser());

  @override
  Future<void> bootstrap() async {
    ref.read(unauthorizedHandlerProvider.notifier).state = onSessionInvalidated;
  }
}

Future<void> pumpRedVecinalApp(
  WidgetTester tester, {
  List<Override> overrides = const [],
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        postReportOutcomeStoreProvider.overrideWithValue(
          InMemoryPostReportOutcomeStore(),
        ),
        ...overrides,
      ],
      child: const RedVecinalApp(),
    ),
  );
}

Future<void> openMainShellAuthenticated(
  WidgetTester tester, {
  FakeNeighborhoodGateway? neighborhoodGateway,
  FakePostGateway? postGateway,
  FakeChatGateway? chatGateway,
}) async {
  await pumpRedVecinalApp(
    tester,
    overrides: [
      authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
      tokenStorageProvider.overrideWithValue(_InMemoryTokenStorage()),
      authControllerProvider.overrideWith(AuthenticatedBootAuthController.new),
      neighborhoodRepositoryProvider.overrideWithValue(
        neighborhoodGateway ?? FakeNeighborhoodGateway(),
      ),
      postRepositoryProvider.overrideWithValue(
        postGateway ??
            FakePostGateway(
              feedPage: const PaginatedFeedPosts(
                items: [],
                currentPage: 1,
                lastPage: 1,
              ),
            ),
      ),
      chatRepositoryProvider.overrideWithValue(
        chatGateway ?? FakeChatGateway(),
      ),
      chatUncertainStoreProvider.overrideWithValue(InMemoryChatUncertainStore()),
    ],
  );
  await tester.pumpAndSettle();
}

class _InMemoryTokenStorage implements TokenStorage {
  @override
  Future<void> deleteToken() async {}

  @override
  Future<String?> readToken() async => '1|preset';

  @override
  Future<void> saveToken(String token) async {}
}

Finder navBarIcon(IconData icon) {
  return find.descendant(
    of: find.byType(NavigationBar),
    matching: find.byIcon(icon),
  );
}
