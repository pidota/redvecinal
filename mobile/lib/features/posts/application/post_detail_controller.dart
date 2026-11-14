import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import '../data/models/post_detail.dart';
import '../data/post_attachment_storage.dart';
import '../data/post_repository.dart';

class PostDetailController
    extends AutoDisposeFamilyAsyncNotifier<PostDetail, int> {
  int _loadGeneration = 0;

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
