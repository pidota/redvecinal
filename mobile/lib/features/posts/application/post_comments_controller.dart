import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import '../data/models/paginated_post_comments.dart';
import '../data/models/post_comment.dart';
import '../data/post_repository.dart';
import 'post_detail_controller.dart';

class PostCommentsController
    extends AutoDisposeFamilyAsyncNotifier<PaginatedPostComments, int> {
  static const _empty = PaginatedPostComments(
    items: [],
    currentPage: 1,
    lastPage: 1,
  );

  bool _loadMoreInFlight = false;
  bool _submitInFlight = false;
  int _listGeneration = 0;
  int _submitGeneration = 0;

  bool get isLoadingMore => _loadMoreInFlight;
  bool get isSubmitting => _submitInFlight;

  @override
  Future<PaginatedPostComments> build(int postId) {
    ref.watch(authControllerProvider);
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return Future.value(_empty);
    }
    return _loadPageGuarded(1, epoch);
  }

  Future<void> refresh() async {
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      state = const AsyncValue.data(_empty);
      return;
    }

    final generation = ++_listGeneration;
    state = const AsyncValue.loading();
    final next = await AsyncValue.guard(() => _loadPageGuarded(1, epoch));
    if (generation != _listGeneration) {
      return;
    }
    state = next;
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null ||
        !current.hasMore ||
        _loadMoreInFlight ||
        state.isLoading) {
      return;
    }

    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return;
    }

    _loadMoreInFlight = true;
    final generation = _listGeneration;
    final nextPage = current.currentPage + 1;
    try {
      final page = await ref
          .read(postRepositoryProvider)
          .listComments(postId: arg, page: nextPage);
      if (neighborhoodSessionEpoch(ref) != epoch ||
          generation != _listGeneration) {
        return;
      }
      state = AsyncValue.data(current.append(page));
    } catch (_) {
      if (neighborhoodSessionEpoch(ref) != epoch ||
          generation != _listGeneration) {
        return;
      }
      state = AsyncValue.data(current);
    } finally {
      _loadMoreInFlight = false;
    }
  }

  Future<ApiFailure?> submitComment(String rawBody) async {
    final body = rawBody.trim();
    if (body.isEmpty) {
      return const ApiValidationFailure(
        {},
        'Escribe un comentario antes de enviar.',
      );
    }
    if (body.length > 5000) {
      return const ApiValidationFailure(
        {},
        'El comentario no puede superar 5000 caracteres.',
      );
    }

    if (_submitInFlight) {
      return null;
    }

    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return null;
    }

    final submitGeneration = ++_submitGeneration;
    _submitInFlight = true;
    try {
      final created = await ref
          .read(postRepositoryProvider)
          .createComment(postId: arg, body: body);
      if (neighborhoodSessionEpoch(ref) != epoch ||
          submitGeneration != _submitGeneration) {
        return null;
      }

      final current = state.valueOrNull ?? _empty;
      await _applyCreatedComment(current, created, epoch);
      return null;
    } on ApiFailure catch (e) {
      if (neighborhoodSessionEpoch(ref) != epoch ||
          submitGeneration != _submitGeneration) {
        return null;
      }
      return e;
    } finally {
      _submitInFlight = false;
    }
  }

  /// Tras POST: mantener el comentario confirmado y ordenar; si ya hay varias
  /// páginas cargadas, rehidratar páginas 1…N desde API para evitar desorden
  /// por fusión offset + append local (H-01).
  Future<void> _applyCreatedComment(
    PaginatedPostComments current,
    PostComment created,
    int epoch,
  ) async {
    if (current.currentPage <= 1) {
      state = AsyncValue.data(current.withAppendedComment(created));
      await _syncEngagementAfterCreate(epoch);
      return;
    }

    final generation = _listGeneration;
    try {
      final seen = <int>{};
      final merged = <PostComment>[];
      var lastPage = current.lastPage;
      for (var page = 1; page <= current.currentPage; page++) {
        final loaded = await ref
            .read(postRepositoryProvider)
            .listComments(postId: arg, page: page);
        if (neighborhoodSessionEpoch(ref) != epoch ||
            generation != _listGeneration) {
          return;
        }
        lastPage = loaded.lastPage;
        for (final comment in loaded.items) {
          if (seen.add(comment.id)) {
            merged.add(comment);
          }
        }
      }
      if (seen.add(created.id)) {
        merged.add(created);
      }
      merged.sort(comparePostCommentsChronologically);
      state = AsyncValue.data(
        PaginatedPostComments(
          items: merged,
          currentPage: current.currentPage,
          lastPage: lastPage,
        ),
      );
    } catch (_) {
      if (neighborhoodSessionEpoch(ref) != epoch ||
          generation != _listGeneration) {
        return;
      }
      state = AsyncValue.data(current.withAppendedComment(created));
    }

    await _syncEngagementAfterCreate(epoch);
  }

  Future<void> _syncEngagementAfterCreate(int epoch) async {
    await ref
        .read(postDetailControllerProvider(arg).notifier)
        .syncEngagementAfterComment(epoch: epoch);
  }

  Future<PaginatedPostComments> _loadPageGuarded(int page, int epoch) async {
    final result = await ref
        .read(postRepositoryProvider)
        .listComments(postId: arg, page: page);
    if (neighborhoodSessionEpoch(ref) != epoch) {
      return _empty;
    }
    return result;
  }
}

final postCommentsControllerProvider = AsyncNotifierProvider.autoDispose
    .family<PostCommentsController, PaginatedPostComments, int>(
      PostCommentsController.new,
    );
