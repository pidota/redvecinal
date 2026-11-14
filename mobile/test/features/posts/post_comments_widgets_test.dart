import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/network/api_failure.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/data/models/paginated_post_comments.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';
import 'package:red_vecinal/features/posts/presentation/post_detail_screen.dart';
import 'package:red_vecinal/features/posts/presentation/widgets/post_comments_section.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

void main() {
  Widget wrap(Widget child, FakePostGateway fake) {
    return ProviderScope(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        postRepositoryProvider.overrideWithValue(fake),
        authControllerProvider.overrideWith(
          AuthenticatedBootAuthController.new,
        ),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    );
  }

  PostDetail detail({
    bool commentsEnabled = true,
    String status = 'published',
  }) {
    final json = Map<String, dynamic>.from(sampleCommunityPostJson());
    json['comments_enabled'] = commentsEnabled;
    json['status'] = status;
    return PostDetail.fromJson(json);
  }

  testWidgets('lista muestra autor y texto', (tester) async {
    final fake = FakePostGateway(
      commentsByPostId: {
        1: sampleCommentsPage(
          items: [sampleComment(body: 'Texto largo '.padRight(400, 'x'))],
        ),
      },
    );

    await tester.pumpWidget(
      wrap(PostCommentsSection(postId: 1, detail: detail()), fake),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pedro Vecino'), findsOneWidget);
    expect(find.textContaining('Texto largo'), findsOneWidget);
  });

  testWidgets('estado vacío', (tester) async {
    final fake = FakePostGateway(
      commentsByPostId: {
        1: const PaginatedPostComments(items: [], currentPage: 1, lastPage: 1),
      },
    );

    await tester.pumpWidget(
      wrap(PostCommentsSection(postId: 1, detail: detail()), fake),
    );
    await tester.pumpAndSettle();

    expect(find.text('Sin comentarios aún'), findsOneWidget);
  });

  testWidgets('error con reintento', (tester) async {
    final fake = FakePostGateway(
      commentsFailureByPostId: {1: const ApiNetworkFailure()},
    );

    await tester.pumpWidget(
      wrap(PostCommentsSection(postId: 1, detail: detail()), fake),
    );
    await tester.pumpAndSettle();

    expect(find.text('No pudimos cargar los comentarios'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets('cargar más visible', (tester) async {
    final fake = FakePostGateway(
      commentsByPostId: {
        1: PaginatedPostComments(
          items: [sampleComment(id: 1)],
          currentPage: 1,
          lastPage: 3,
        ),
      },
    );

    await tester.pumpWidget(
      wrap(PostCommentsSection(postId: 1, detail: detail()), fake),
    );
    await tester.pumpAndSettle();

    expect(find.text('Cargar más comentarios'), findsOneWidget);
  });

  testWidgets('compositor deshabilitado si comments_enabled false', (
    tester,
  ) async {
    final fake = FakePostGateway();
    await tester.pumpWidget(
      wrap(
        PostCommentsSection(postId: 1, detail: detail(commentsEnabled: false)),
        fake,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Publicar comentario'), findsNothing);
    expect(
      find.textContaining('comentarios nuevos están deshabilitados'),
      findsOneWidget,
    );
  });

  testWidgets('compositor envía comentario', (tester) async {
    final fake = FakePostGateway();
    await tester.pumpWidget(
      wrap(PostCommentsSection(postId: 1, detail: detail()), fake),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Mi aporte');
    await tester.tap(find.text('Publicar comentario'));
    await tester.pumpAndSettle();

    expect(fake.createCommentCallCount, 1);
    expect(find.text('Comentario publicado.'), findsOneWidget);
  });

  testWidgets('validación no envía vacío', (tester) async {
    final fake = FakePostGateway();
    await tester.pumpWidget(
      wrap(PostCommentsSection(postId: 1, detail: detail()), fake),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Publicar comentario'));
    await tester.pump();
    expect(fake.createCommentCallCount, 0);
    expect(find.text('Escribe un comentario antes de enviar.'), findsOneWidget);
  });

  testWidgets('pantalla pequeña integra sección en detalle', (tester) async {
    final fake = FakePostGateway(
      detailById: {2: sampleCommunityPostDetail(id: 2)},
    );

    await tester.binding.setSurfaceSize(const Size(360, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appConfigProvider.overrideWithValue(testAppConfig),
          authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
          postRepositoryProvider.overrideWithValue(fake),
          authControllerProvider.overrideWith(
            AuthenticatedBootAuthController.new,
          ),
        ],
        child: MediaQuery(
          data: const MediaQueryData(size: Size(360, 900)),
          child: const MaterialApp(home: PostDetailScreen(postId: 2)),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Comentarios'), findsOneWidget);
    expect(find.text('Pedro Vecino'), findsOneWidget);
  });
}
