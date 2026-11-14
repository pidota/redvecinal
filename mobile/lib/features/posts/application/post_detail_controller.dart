import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import '../data/models/feed_post.dart';
import '../data/models/post_detail.dart';
import '../data/post_attachment_storage.dart';
import '../data/post_repository.dart';
import 'feed_controller.dart';

class PostDetailController
    extends AutoDisposeFamilyAsyncNotifier<PostDetail, int> {
  int _loadGeneration = 0;
  bool _reactionInFlight = false;
  int _reactionGeneration = 0;

  bool get isReactionInFlight => _reactionInFlight;

  @override
  Future<PostDetail> build(int postId) {
    ref.watch(authControllerProvider);
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return Future.error(StateError('Sin sesión'));
    }
    return _load(postId, epoch);
  }

  Future<void> refresh() async {
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      state = AsyncValue.error(StateError('Sin sesión'), StackTrace.current);
      return;
    }

    final generation = ++_loadGeneration;
    state = const AsyncValue.loading();
    final next = await AsyncValue.guard(() => _load(arg, epoch));
    if (generation != _loadGeneration) {
      return;
    }
    state = next;
  }

  Future<PostAttachmentDownloadResult> downloadAttachment(
    PostAttachment attachment,
  ) async {
    final epochBefore = neighborhoodSessionEpoch(ref);
    final auth = ref.read(authControllerProvider);
    if (epochBefore == null || auth is! AuthAuthenticated) {
      return const PostAttachmentDownloadResult.sessionEnded();
    }
    final userId = auth.user.id;

    try {
      final bytes = await ref
          .read(postRepositoryProvider)
          .downloadAttachment(
            postId: arg,
            attachmentId: attachment.id,
            relativePath: attachment.relativeDownloadPath,
          );

      if (neighborhoodSessionEpoch(ref) != epochBefore) {
        return const PostAttachmentDownloadResult.sessionEnded();
      }

      final authAfterDownload = ref.read(authControllerProvider);
      if (authAfterDownload is! AuthAuthenticated ||
          authAfterDownload.user.id != userId) {
        await ref.read(postAttachmentStorageProvider).invalidate();
        return const PostAttachmentDownloadResult.sessionEnded();
      }

      final storage = ref.read(postAttachmentStorageProvider);
      final saved = await storage.saveForSession(
        sessionEpoch: epochBefore,
        userId: userId,
        fileName: '${attachment.id}_${attachment.sanitizedFileName}',
        bytes: bytes,
      );

      if (neighborhoodSessionEpoch(ref) != epochBefore) {
        await storage.invalidate();
        return const PostAttachmentDownloadResult.sessionEnded();
      }

      final authAfterSave = ref.read(authControllerProvider);
      if (authAfterSave is! AuthAuthenticated ||
          authAfterSave.user.id != userId) {
        await storage.invalidate();
        return const PostAttachmentDownloadResult.sessionEnded();
      }

      if (saved.sessionInvalidated) {
        return const PostAttachmentDownloadResult.sessionEnded();
      }
      if (saved.failed || !saved.saved) {
        return const PostAttachmentDownloadResult.failed();
      }

      return PostAttachmentDownloadResult.success(saved.path!);
    } catch (_) {
      if (neighborhoodSessionEpoch(ref) != epochBefore) {
        return const PostAttachmentDownloadResult.sessionEnded();
      }
      rethrow;
    }
  }

  Future<PostDetail> _load(int postId, int epoch) async {
    final detail = await ref.read(postRepositoryProvider).getPost(postId);
    if (neighborhoodSessionEpoch(ref) != epoch) {
      throw StateError('Respuesta de sesión anterior');
    }
    return detail;
  }

  Future<ApiFailure?> setLikeReaction() => _mutateReaction(addingLike: true);

  Future<ApiFailure?> removeLikeReaction() =>
      _mutateReaction(addingLike: false);

  Future<ApiFailure?> toggleLikeReaction() async {
    final engagement = state.valueOrNull?.engagement;
    if (engagement == null) {
      return null;
    }
    if (engagement.hasLike) {
      return removeLikeReaction();
    }
    return setLikeReaction();
  }

  Future<ApiFailure?> _mutateReaction({required bool addingLike}) async {
    if (_reactionInFlight) {
      return null;
    }

    final current = state.valueOrNull;
    if (current == null || !current.isPublished) {
      return null;
    }

    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return null;
    }

    final previous = current;
    final optimistic = _optimisticEngagement(
      current.engagement,
      addingLike: addingLike,
    );
    state = AsyncValue.data(current.copyWithEngagement(optimistic));

    final reactionGeneration = ++_reactionGeneration;
    _reactionInFlight = true;
    try {
      if (addingLike) {
        await ref.read(postRepositoryProvider).setReaction(postId: arg);
      } else {
        await ref.read(postRepositoryProvider).removeReaction(postId: arg);
      }

      if (neighborhoodSessionEpoch(ref) != epoch ||
          reactionGeneration != _reactionGeneration) {
        // No restaurar `previous`: podría sobrescribir el detalle del usuario nuevo.
        return null;
      }

      await _syncEngagementAfterReaction(epoch);
      return null;
    } on ApiFailure catch (e) {
      if (neighborhoodSessionEpoch(ref) != epoch ||
          reactionGeneration != _reactionGeneration) {
        return null;
      }
      state = AsyncValue.data(previous);
      return e;
    } finally {
      _reactionInFlight = false;
    }
  }

  FeedPostEngagement _optimisticEngagement(
    FeedPostEngagement current, {
    required bool addingLike,
  }) {
    if (addingLike) {
      final alreadyCounted = current.myReactionType != null;
      final nextCount =
          alreadyCounted ? current.reactionsCount : current.reactionsCount + 1;
      return current.copyWith(
        myReactionType: 'like',
        reactionsCount: nextCount,
      );
    }

    final nextCount =
        current.myReactionType == 'like'
            ? (current.reactionsCount - 1).clamp(0, 1 << 30)
            : current.reactionsCount;
    return current.copyWith(reactionsCount: nextCount, clearMyReaction: true);
  }

  Future<void> _syncEngagementAfterReaction(int epoch) async {
    final generation = ++_loadGeneration;
    try {
      final detail = await ref.read(postRepositoryProvider).getPost(arg);
      if (neighborhoodSessionEpoch(ref) != epoch ||
          generation != _loadGeneration) {
        return;
      }
      state = AsyncValue.data(detail);
    } catch (_) {
      // Conservar optimista si el refresh falla; el usuario puede reintentar.
    }
    if (neighborhoodSessionEpoch(ref) == epoch) {
      ref.invalidate(feedControllerProvider);
    }
  }
}

class PostAttachmentDownloadResult {
  const PostAttachmentDownloadResult._({
    required this.savedPath,
    required this.sessionEnded,
    required this.failed,
  });

  const PostAttachmentDownloadResult.success(String path)
    : this._(savedPath: path, sessionEnded: false, failed: false);

  const PostAttachmentDownloadResult.sessionEnded()
    : this._(savedPath: null, sessionEnded: true, failed: false);

  const PostAttachmentDownloadResult.failed()
    : this._(savedPath: null, sessionEnded: false, failed: true);

  final String? savedPath;
  final bool sessionEnded;
  final bool failed;
}

final postDetailControllerProvider = AsyncNotifierProvider.autoDispose
    .family<PostDetailController, PostDetail, int>(PostDetailController.new);
