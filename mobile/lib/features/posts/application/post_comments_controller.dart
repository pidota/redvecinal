import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import '../data/models/paginated_post_comments.dart';
import '../data/post_repository.dart';
import 'feed_controller.dart';
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
      state = AsyncValue.data(current.withAppendedComment(created));

      await _syncEngagementAfterCreate(epoch);
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

  Future<void> _syncEngagementAfterCreate(int epoch) async {
    try {
      await ref.read(postDetailControllerProvider(arg).notifier).refresh();
    } catch (_) {
      // Conservar comentario en lista; el usuario puede refrescar detalle.
    }
    if (neighborhoodSessionEpoch(ref) == epoch) {
      ref.invalidate(feedControllerProvider);
    }
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
