import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/application/auth_controller.dart';
import '../../features/auth/domain/auth_state.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/session_retry_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/chat/presentation/chat_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/neighborhoods/presentation/neighborhood_detail_invalid_route_screen.dart';
import '../../features/neighborhoods/presentation/neighborhood_detail_screen.dart';
import '../../features/neighborhoods/presentation/group_membership_review_screen.dart';
import '../../features/neighborhoods/presentation/neighborhood_join_screen.dart';
import '../../features/neighborhoods/presentation/neighborhoods_screen.dart';
import '../../features/neighborhoods/presentation/reviewable_groups_screen.dart';
import '../../features/posts/presentation/posts_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import 'main_shell_scaffold.dart';
import 'router_refresh.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');

String? _authRedirect(GoRouterState state, AuthState auth) {
  final path = state.matchedLocation;

  switch (auth) {
    case AuthInitializing():
      if (path != '/splash') {
        return '/splash';
      }
      return null;
    case AuthAuthenticating():
      if (path != '/login') {
        return '/login';
      }
      return null;
    case AuthUnauthenticated():
      if (path == '/login') {
        return null;
      }
      return '/login';
    case AuthRecoverableError():
      if (path == '/session-retry') {
        return null;
      }
      return '/session-retry';
    case AuthAuthenticated():
      if (path == '/login' || path == '/splash' || path == '/session-retry') {
        return '/home';
      }
      return null;
  }
}

final appRouterProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(routerRefreshListenableProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/splash',
    refreshListenable: refresh,
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      return _authRedirect(state, auth);
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/session-retry',
        builder: (context, state) => const SessionRetryScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) {
          return MainShellScaffold(navigationShell: navigationShell);
        },
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/home',
                builder: (context, state) => const HomeScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/neighborhoods',
                builder: (context, state) => const NeighborhoodsScreen(),
                routes: [
                  GoRoute(
                    path: 'review',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const ReviewableGroupsScreen(),
                  ),
                  GoRoute(
                    path: ':groupId/review-requests',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) {
                      final raw = state.pathParameters['groupId'] ?? '';
                      final id = int.tryParse(raw);
                      if (id == null) {
                        return const NeighborhoodDetailInvalidRouteScreen();
                      }
                      return GroupMembershipReviewScreen(groupId: id);
                    },
                  ),
                  GoRoute(
                    path: ':groupId/join',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) {
                      final raw = state.pathParameters['groupId'] ?? '';
                      final id = int.tryParse(raw);
                      if (id == null) {
                        return const NeighborhoodDetailInvalidRouteScreen();
                      }
                      return NeighborhoodJoinScreen(groupId: id);
                    },
                  ),
                  GoRoute(
                    path: ':groupId',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) {
                      final raw = state.pathParameters['groupId'] ?? '';
                      final id = int.tryParse(raw);
                      if (id == null) {
                        return const NeighborhoodDetailInvalidRouteScreen();
                      }
                      return NeighborhoodDetailScreen(groupId: id);
                    },
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/posts',
                builder: (context, state) => const PostsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/chat',
                builder: (context, state) => const ChatScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/profile',
                builder: (context, state) => const ProfileScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
});
