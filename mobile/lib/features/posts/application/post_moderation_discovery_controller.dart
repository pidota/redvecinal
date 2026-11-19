import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import '../data/post_repository.dart';

/// Visibilidad de la entrada «Moderar publicaciones» en detalle de junta.
///
/// La autorización definitiva corresponde al backend; aquí solo se infiere si
/// conviene mostrar el acceso a partir de junta activa + sondeo de cola (pág. 1).
enum PostModerationDiscoveryVisibility { hidden, visible }

@immutable
class PostModerationDiscoveryKey {
  const PostModerationDiscoveryKey({
    required this.groupId,
    required this.groupStatus,
  });

  final int groupId;
  final String groupStatus;

  @override
  bool operator ==(Object other) {
    return other is PostModerationDiscoveryKey &&
        other.groupId == groupId &&
        other.groupStatus == groupStatus;
  }

  @override
  int get hashCode => Object.hash(groupId, groupStatus);
}

class PostModerationDiscoveryState {
  const PostModerationDiscoveryState({required this.visibility});

  final PostModerationDiscoveryVisibility visibility;

  static const hidden = PostModerationDiscoveryState(
    visibility: PostModerationDiscoveryVisibility.hidden,
  );

  static const visible = PostModerationDiscoveryState(
    visibility: PostModerationDiscoveryVisibility.visible,
  );
}

class PostModerationDiscoveryController
    extends
        AutoDisposeFamilyAsyncNotifier<
          PostModerationDiscoveryState,
          PostModerationDiscoveryKey
        > {
  int _probeGeneration = 0;

  @override
  Future<PostModerationDiscoveryState> build(PostModerationDiscoveryKey key) {
    ref.watch(authControllerProvider);
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return Future.value(PostModerationDiscoveryState.hidden);
    }
    if (key.groupStatus != 'active') {
      return Future.value(PostModerationDiscoveryState.hidden);
    }
    return _probeQueueAccess(key.groupId, epoch);
  }

  Future<PostModerationDiscoveryState> _probeQueueAccess(
    int groupId,
    int epoch,
  ) async {
    final generation = ++_probeGeneration;
    try {
      await ref
          .read(postRepositoryProvider)
          .listPendingPosts(groupId: groupId, page: 1);
      if (neighborhoodSessionEpoch(ref) != epoch ||
          generation != _probeGeneration) {
        return PostModerationDiscoveryState.hidden;
      }
      return PostModerationDiscoveryState.visible;
    } on ApiForbiddenFailure {
      return PostModerationDiscoveryState.hidden;
    } on ApiNotFoundFailure {
      return PostModerationDiscoveryState.hidden;
    } on ApiSessionExpiredFailure {
      rethrow;
    } on Object {
      // Red, tiempo de espera o 5xx: no asumir autorización ni denegación.
      return PostModerationDiscoveryState.hidden;
    }
  }
}

final postModerationDiscoveryControllerProvider = AsyncNotifierProvider
    .autoDispose
    .family<
      PostModerationDiscoveryController,
      PostModerationDiscoveryState,
      PostModerationDiscoveryKey
    >(PostModerationDiscoveryController.new);
