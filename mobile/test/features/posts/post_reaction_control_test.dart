import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/application/post_detail_controller.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';
import 'package:red_vecinal/features/posts/presentation/widgets/post_reaction_control.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

void main() {
  Widget wrap(Widget child, FakePostGateway gateway) {
    return ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        postRepositoryProvider.overrideWithValue(gateway),
        authControllerProvider.overrideWith(
          AuthenticatedBootAuthController.new,
        ),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  testWidgets('muestra botón inactivo', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: detailWithEngagement(id: 1)},
    );
    await tester.pumpWidget(
      wrap(
        PostReactionControl(postId: 1, detail: detailWithEngagement(id: 1)),
        gateway,
      ),
    );

    expect(find.byIcon(Icons.favorite_border), findsOneWidget);
  });

  testWidgets('muestra botón activo', (tester) async {
    final detail = detailWithEngagement(
      id: 1,
      myReactionType: 'like',
      reactionsCount: 2,
    );
    final gateway = FakePostGateway(detailById: {1: detail});
    await tester.pumpWidget(
      wrap(PostReactionControl(postId: 1, detail: detail), gateway),
    );

    expect(find.byIcon(Icons.favorite), findsOneWidget);
  });

  testWidgets('tap envía like', (tester) async {
    final details = {1: detailWithEngagement(id: 1)};
    final gateway = FakePostGateway(
      detailById: details,
      onSetReaction: (id, _) {
        details[id] = detailWithEngagement(
          id: id,
          reactionsCount: 1,
          myReactionType: 'like',
        );
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(testAppConfig),
          authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
          postRepositoryProvider.overrideWithValue(gateway),
          authControllerProvider.overrideWith(
            AuthenticatedBootAuthController.new,
          ),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) {
                final detail =
                    ref.watch(postDetailControllerProvider(1)).value ??
                    detailWithEngagement(id: 1);
                return PostReactionControl(postId: 1, detail: detail);
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();

    expect(gateway.setReactionCallCount, 1);
  });

  testWidgets('error muestra snackbar', (tester) async {
    final gateway = FakePostGateway(
      detailById: {1: detailWithEngagement(id: 1)},
      setReactionFailureByPostId: {
        1: const ApiForbiddenFailure('No permitido'),
      },
    );

    await tester.pumpWidget(
      wrap(
        PostReactionControl(postId: 1, detail: detailWithEngagement(id: 1)),
        gateway,
      ),
    );

    await tester.tap(find.byIcon(Icons.favorite_border));
    await tester.pumpAndSettle();

    expect(find.text('No permitido'), findsOneWidget);
  });

  testWidgets('post no publicado sin botón interactivo', (tester) async {
    final json = Map<String, dynamic>.from(sampleCommunityPostJson());
    json['status'] = 'pending';
    final detail = PostDetail.fromJson(json);
    final gateway = FakePostGateway(detailById: {1: detail});

    await tester.pumpWidget(
      wrap(PostReactionControl(postId: 1, detail: detail), gateway),
    );

    expect(find.byIcon(Icons.favorite), findsNothing);
    expect(find.textContaining('reacciones'), findsOneWidget);
  });

  testWidgets('pantalla estrecha', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final gateway = FakePostGateway(
      detailById: {1: detailWithEngagement(id: 1, reactionsCount: 5)},
    );
    await tester.pumpWidget(
      wrap(
        PostReactionControl(
          postId: 1,
          detail: detailWithEngagement(id: 1, reactionsCount: 5),
        ),
        gateway,
      ),
    );

    expect(find.text('5 reacciones'), findsOneWidget);
  });
}
