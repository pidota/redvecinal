import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import '../data/chat_repository.dart';
import '../data/chat_timeline.dart';
import '../data/models/chat_message.dart';
import 'chat_access.dart';
import 'chat_trusted_window.dart';

class ChatRoomHistoryState {
  const ChatRoomHistoryState({
    required this.roomId,
    this.timeline = const ChatTimeline(),
    this.accessRevoked = false,
    this.caughtUpNewer = true,
    this.hasOlder = false,
    this.isLoadingOlder = false,
    this.isRefreshingNewer = false,
    this.trustedMaxId,
  });

  final int roomId;
  final ChatTimeline timeline;
  final bool accessRevoked;

  /// Tras la carga inicial (últimos N) el cliente está en el extremo reciente.
  /// Pasa a false si `refreshNewer()` devuelve una página llena (`limit`).
  final bool caughtUpNewer;

  /// Conservador: una página llena en dirección antigua sugiere que puede haber más.
  /// El API no expone un flag `has_more`; una página corta o vacía lo pone en false.
  final bool hasOlder;
  final bool isLoadingOlder;
  final bool isRefreshingNewer;

  /// Límite superior acreditado por páginas REST conectadas. No es timeline.maxId.
  final int? trustedMaxId;

  ChatRoomHistoryState copyWith({
    ChatTimeline? timeline,
    bool? accessRevoked,
    bool? caughtUpNewer,
    bool? hasOlder,
    bool? isLoadingOlder,
    bool? isRefreshingNewer,
    int? trustedMaxId,
  }) {
    return ChatRoomHistoryState(
      roomId: roomId,
      timeline: timeline ?? this.timeline,
      accessRevoked: accessRevoked ?? this.accessRevoked,
      caughtUpNewer: caughtUpNewer ?? this.caughtUpNewer,
      hasOlder: hasOlder ?? this.hasOlder,
      isLoadingOlder: isLoadingOlder ?? this.isLoadingOlder,
      isRefreshingNewer: isRefreshingNewer ?? this.isRefreshingNewer,
      trustedMaxId: trustedMaxId ?? this.trustedMaxId,
    );
  }
}

class ChatRoomHistoryController
    extends AutoDisposeFamilyAsyncNotifier<ChatRoomHistoryState, int> {
  int _generation = 0;

  @override
  Future<ChatRoomHistoryState> build(int roomId) {
    _generation++;
    ref.watch(authControllerProvider);
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return Future.value(ChatRoomHistoryState(roomId: roomId));
    }
    if (ref.read(chatRevokedRoomIdsProvider).contains(roomId)) {
      return Future.value(
        ChatRoomHistoryState(roomId: roomId, accessRevoked: true),
      );
    }
    return _loadInitial(roomId, epoch);
  }

  Future<void> refresh() async {
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      state = AsyncValue.data(ChatRoomHistoryState(roomId: arg));
      return;
    }
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadInitial(arg, epoch));
  }

  /// Pensado para invocarse cuando exista `chat.sync` (REST only en 5.5.3).
  Future<void> refreshNewer() async {
    final epoch = neighborhoodSessionEpoch(ref);
    final current = state.valueOrNull;
    if (epoch == null || current == null || current.accessRevoked) {
      return;
    }
    final generation = ++_generation;
    state = AsyncValue.data(current.copyWith(isRefreshingNewer: true));
    try {
      final afterId = current.trustedMaxId;
      if (afterId == null) {
        state = AsyncValue.data(current.copyWith(isRefreshingNewer: false));
        return;
      }
      final page = await ref.read(chatRepositoryProvider).listMessages(
            roomId: arg,
            afterId: afterId,
          );
      if (neighborhoodSessionEpoch(ref) != epoch || generation != _generation) {
        return;
      }
      final latest = state.valueOrNull ?? current;
      if (latest.accessRevoked) {
        return;
      }
      final merged = latest.timeline.merge(page.messages, roomId: arg);
      final trusted = advanceTrustedMaxId(
        currentTrustedMaxId: latest.trustedMaxId ?? current.trustedMaxId,
        requestedAfterId: afterId,
        pageMessages: page.messages,
        roomId: arg,
      );
      state = AsyncValue.data(
        latest.copyWith(
          timeline: merged,
          caughtUpNewer: !page.mayHaveMore,
          isRefreshingNewer: false,
          trustedMaxId: trusted,
        ),
      );
    } on ApiForbiddenFailure {
      if (neighborhoodSessionEpoch(ref) != epoch || generation != _generation) {
        return;
      }
      markAccessRevoked();
    } on ApiSessionExpiredFailure {
      if (generation != _generation) {
        return;
      }
      state = AsyncValue.data(ChatRoomHistoryState(roomId: arg));
    } on ApiFailure {
      final latest = state.valueOrNull ?? current;
      state = AsyncValue.data(latest.copyWith(isRefreshingNewer: false));
    }
  }

  Future<void> loadOlder() async {
    final epoch = neighborhoodSessionEpoch(ref);
    final current = state.valueOrNull;
    if (epoch == null ||
        current == null ||
        current.accessRevoked ||
        current.isLoadingOlder) {
      return;
    }
    final minId = current.timeline.minId;
    if (minId == null) {
      return;
    }
    final generation = ++_generation;
    state = AsyncValue.data(current.copyWith(isLoadingOlder: true));
    try {
      final page = await ref.read(chatRepositoryProvider).listMessages(
            roomId: arg,
            beforeId: minId,
          );
      if (neighborhoodSessionEpoch(ref) != epoch || generation != _generation) {
        return;
      }
      state = AsyncValue.data(
        current.copyWith(
          timeline: current.timeline.merge(page.messages, roomId: arg),
          hasOlder: page.mayHaveMore,
          isLoadingOlder: false,
        ),
      );
    } on ApiForbiddenFailure {
      if (neighborhoodSessionEpoch(ref) != epoch) {
        return;
      }
      markAccessRevoked();
    } on ApiFailure {
      final latest = state.valueOrNull ?? current;
      state = AsyncValue.data(latest.copyWith(isLoadingOlder: false));
    }
  }

  void markAccessRevoked() {
    revokeChatRoomAccess(ref, arg);
    state = AsyncValue.data(
      ChatRoomHistoryState(roomId: arg, accessRevoked: true),
    );
  }

  /// Incorpora un mensaje confirmado por REST sin duplicar por id/versión.
  void ingestConfirmed(ChatMessage message) {
    final current = state.valueOrNull;
    if (current == null ||
        current.accessRevoked ||
        message.chatRoomId != arg) {
      return;
    }
    state = AsyncValue.data(
      current.copyWith(
        timeline: current.timeline.merge([message], roomId: arg),
      ),
    );
  }

  Future<ChatRoomHistoryState> _loadInitial(int roomId, int epoch) async {
    try {
      final page = await ref.read(chatRepositoryProvider).listMessages(
            roomId: roomId,
          );
      if (neighborhoodSessionEpoch(ref) != epoch) {
        return ChatRoomHistoryState(roomId: roomId);
      }
      final timeline = const ChatTimeline().merge(page.messages, roomId: roomId);
      return ChatRoomHistoryState(
        roomId: roomId,
        timeline: timeline,
        caughtUpNewer: true,
        hasOlder: page.mayHaveMore,
        trustedMaxId: timeline.maxId,
      );
    } on ApiForbiddenFailure {
      revokeChatRoomAccess(ref, roomId);
      return ChatRoomHistoryState(roomId: roomId, accessRevoked: true);
    } on ApiSessionExpiredFailure {
      return ChatRoomHistoryState(roomId: roomId);
    }
  }
}

final chatRoomHistoryControllerProvider = AsyncNotifierProvider.autoDispose
    .family<ChatRoomHistoryController, ChatRoomHistoryState, int>(
  ChatRoomHistoryController.new,
);
