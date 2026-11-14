import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:red_vecinal/core/config/app_config.dart';
import 'package:red_vecinal/core/storage/secure_token_storage.dart';
import 'package:red_vecinal/features/auth/application/auth_controller.dart';
import 'package:red_vecinal/features/auth/data/auth_repository.dart';
import 'package:red_vecinal/features/posts/application/post_comments_controller.dart';
import 'package:red_vecinal/features/posts/application/post_detail_controller.dart';
import 'package:red_vecinal/features/posts/data/models/post_detail.dart';
import 'package:red_vecinal/features/posts/data/post_repository.dart';

import '../../test_helpers.dart';
import '../auth/auth_test_support.dart';
import 'post_test_support.dart';

void main() {
  ProviderContainer container(FakePostGateway gateway) {
    return ProviderContainer(
      overrides: [
        appConfigProvider.overrideWithValue(testAppConfig),
        authRepositoryProvider.overrideWithValue(FakeAuthGateway()),
        tokenStorageProvider.overrideWithValue(InMemoryTokenStorage()),
        postRepositoryProvider.overrideWithValue(gateway),
        authControllerProvider.overrideWith(
          AuthenticatedBootAuthController.new,
        ),
      ],
    );
  }

  test(
    'PUT like en vuelo + POST comentario conserva reacción optimista',
    () async {
      final details = {
        1: detailWithEngagement(id: 1, reactionsCount: 0, myReactionType: null),
      };
      final gateway = FakePostGateway(
        detailById: details,
        detailDelayMs: 30,
      reactionDelayMs: 120,
      onSetReaction: (id, _) {
        final json = Map<String, dynamic>.from(
          sampleCommunityPostJson(id: id),
        );
        json['engagement'] = {
          'comments_count': 3,
          'reactions_count': 1,
          'my_reaction': {'type': 'like'},
        };
        details[id] = PostDetail.fromJson(json);
      },
      onCreateComment: (id, _) {
        final json = Map<String, dynamic>.from(
          sampleCommunityPostJson(id: id),
        );
        json['engagement'] = {
          'comments_count': 3,
          'reactions_count': 0,
          'my_reaction': null,
        };
        details[id] = PostDetail.fromJson(json);
      },
      );
      final c = container(gateway);
      addTearDown(c.dispose);
      c.listen(postDetailControllerProvider(1), (_, __) {});

      await c.read(postDetailControllerProvider(1).future);
      await c.read(postCommentsControllerProvider(1).future);

      final likeFuture =
          c.read(postDetailControllerProvider(1).notifier).setLikeReaction();
      await c
          .read(postCommentsControllerProvider(1).notifier)
          .submitComment('Concurrente');

      final detailDuring = c.read(postDetailControllerProvider(1)).valueOrNull;
      expect(detailDuring?.engagement.hasLike, isTrue);

      await likeFuture;
      final detailFinal = c.read(postDetailControllerProvider(1)).value!;
      expect(detailFinal.engagement.hasLike, isTrue);
      expect(detailFinal.engagement.commentsCount, 3);
    },
  );

  test(
    'DELETE like en vuelo + POST comentario conserva estado intermedio',
    () async {
      final details = {
        1: detailWithEngagement(
          id: 1,
          reactionsCount: 2,
          myReactionType: 'like',
        ),
      };
      final gateway = FakePostGateway(
        detailById: details,
        reactionDelayMs: 120,
        onRemoveReaction: (id) {
          details[id] = detailWithEngagement(id: id, reactionsCount: 1);
        },
        onCreateComment: (id, _) {
          final json = Map<String, dynamic>.from(
            sampleCommunityPostJson(id: id),
          );
          json['engagement'] = {
            'comments_count': 5,
            'reactions_count': 2,
            'my_reaction': {'type': 'like'},
          };
          details[id] = PostDetail.fromJson(json);
        },
      );
      final c = container(gateway);
      addTearDown(c.dispose);
      c.listen(postDetailControllerProvider(1), (_, __) {});

      await c.read(postDetailControllerProvider(1).future);
      await c.read(postCommentsControllerProvider(1).future);

      final unlikeFuture =
          c.read(postDetailControllerProvider(1).notifier).removeLikeReaction();
      await c
          .read(postCommentsControllerProvider(1).notifier)
          .submitComment('Otro');

      final interim = c.read(postDetailControllerProvider(1)).value!;
      expect(interim.engagement.hasLike, isFalse);
      expect(interim.engagement.commentsCount, 5);

      await unlikeFuture;
      final end = c.read(postDetailControllerProvider(1)).value!;
      expect(end.engagement.hasLike, isFalse);
      expect(end.engagement.reactionsCount, 1);
    },
  );

  test('refresh manual durante PUT no pierde like optimista', () async {
    final details = {
      1: detailWithEngagement(id: 1, reactionsCount: 0, myReactionType: null),
    };
    final gateway = FakePostGateway(
      detailById: details,
      detailDelayMs: 50,
      reactionDelayMs: 100,
      onSetReaction: (id, _) {
        final json = Map<String, dynamic>.from(
          sampleCommunityPostJson(id: id),
        );
        json['engagement'] = {
          'comments_count': 3,
          'reactions_count': 1,
          'my_reaction': {'type': 'like'},
        };
        details[id] = PostDetail.fromJson(json);
      },
    );
    final c = container(gateway);
    addTearDown(c.dispose);
    c.listen(postDetailControllerProvider(1), (_, __) {});

    await c.read(postDetailControllerProvider(1).future);
    final refreshFuture =
        c.read(postDetailControllerProvider(1).notifier).refresh();
    final likeFuture =
        c.read(postDetailControllerProvider(1).notifier).setLikeReaction();

    await likeFuture;
    await refreshFuture;

    final detail = c.read(postDetailControllerProvider(1)).value!;
    expect(detail.engagement.hasLike, isTrue);
  });

  test(
    'sync de comentario con GET fallido incrementa comments_count una vez',
    () async {
    final gateway = FakePostGateway(
      detailById: {1: detailWithEngagement(id: 1)},
      detailFailureAfterCalls: 1,
    );
      final c = container(gateway);
      addTearDown(c.dispose);
      c.listen(postDetailControllerProvider(1), (_, __) {});

      await c.read(postDetailControllerProvider(1).future);
      await c.read(postCommentsControllerProvider(1).future);

      final before = c.read(postDetailControllerProvider(1)).value!;
      await c
          .read(postCommentsControllerProvider(1).notifier)
          .submitComment('Fallo sync');

      final after = c.read(postDetailControllerProvider(1)).value!;
      expect(
        after.engagement.commentsCount,
        before.engagement.commentsCount + 1,
      );
    },
  );

  test('POST comentario no deja detalle en loading global', () async {
    final gateway = FakePostGateway(
      detailById: {1: detailWithEngagement(id: 1)},
      detailDelayMs: 80,
    );
    final c = container(gateway);
    addTearDown(c.dispose);
    var loadingDuring = false;
    c.listen(postDetailControllerProvider(1), (prev, next) {
      if (next.isLoading && next.valueOrNull != null) {
        loadingDuring = true;
      }
    }, fireImmediately: true);

    await c.read(postDetailControllerProvider(1).future);
    await c.read(postCommentsControllerProvider(1).future);
    await c
        .read(postCommentsControllerProvider(1).notifier)
        .submitComment('Sin loading');

    expect(loadingDuring, isFalse);
    expect(c.read(postDetailControllerProvider(1)).hasValue, isTrue);
  });
}
