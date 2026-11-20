import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import '../data/chat_repository.dart';
import '../data/models/chat_message.dart';
import 'chat_access.dart';
import 'chat_read_frontier.dart';
import 'chat_room_history_controller.dart';
import 'chat_unread_controller.dart';

enum ChatReadTrigger { layout, scroll, resume, refresh, route }

class ChatReadSighting {
  const ChatReadSighting({
    required this.roomId,
    required this.userId,
    required this.message,
    required this.appResumed,
    required this.routeCurrent,
    required this.trigger,
  });

  final int roomId;
  final int userId;
  final ChatMessage message;
  final bool appResumed;
  final bool routeCurrent;
  final ChatReadTrigger trigger;

  bool get isEligible {
    return appResumed &&
        routeCurrent &&
        message.id > 0 &&
        message.chatRoomId == roomId;
  }
}

class ChatReadMarkState {
  const ChatReadMarkState({
    this.confirmedCursor,
    this.candidateCursor,
    this.inFlightCursor,
    this.accessRevoked = false,
    this.lastFailure,
    this.presentedMessageIds = const {},
  });

  final int? confirmedCursor;
  final int? candidateCursor;
  final int? inFlightCursor;
  final bool accessRevoked;
  final ApiFailure? lastFailure;
  final Set<int> presentedMessageIds;

  bool get inFlight => inFlightCursor != null;

  ChatReadMarkState copyWith({
    int? confirmedCursor,
    int? candidateCursor,
    int? inFlightCursor,
    bool? accessRevoked,
    ApiFailure? lastFailure,
    Set<int>? presentedMessageIds,
    bool clearInFlight = false,
    bool clearCandidate = false,
    bool clearFailure = false,
  }) {
    return ChatReadMarkState(
      confirmedCursor: confirmedCursor ?? this.confirmedCursor,
      candidateCursor: clearCandidate ? null : (candidateCursor ?? this.candidateCursor),
      inFlightCursor: clearInFlight ? null : (inFlightCursor ?? this.inFlightCursor),
      accessRevoked: accessRevoked ?? this.accessRevoked,
      lastFailure: clearFailure ? null : (lastFailure ?? this.lastFailure),
      presentedMessageIds: presentedMessageIds ?? this.presentedMessageIds,
    );
  }
}

class ChatReadCoordinator
    extends AutoDisposeFamilyNotifier<ChatReadMarkState, int> {
  int _generation = 0;
  int? _unconfirmedAttemptId;
  int? _boundUserId;
  int? _confirmedCursor;
  Set<int> _presentedIds = {};
  KeepAliveLink? _keepAlive;

  @override
  ChatReadMarkState build(int roomId) {
    _generation++;
    ref.watch(authControllerProvider);
    ref.watch(chatRevokedRoomIdsProvider);
    final epoch = neighborhoodSessionEpoch(ref);
    final auth = ref.read(authControllerProvider);
    final userId = auth is AuthAuthenticated ? auth.user.id : null;
    if (epoch == null || userId == null) {
      _boundUserId = null;
      _confirmedCursor = null;
      _presentedIds = {};
      _unconfirmedAttemptId = null;
      return const ChatReadMarkState();
    }
    if (userId != _boundUserId) {
      _boundUserId = userId;
      _confirmedCursor = null;
      _presentedIds = {};
      _unconfirmedAttemptId = null;
    }
    if (ref.read(chatRevokedRoomIdsProvider).contains(roomId)) {
      return ChatReadMarkState(
        accessRevoked: true,
        presentedMessageIds: _presentedIds,
      );
    }
    return ChatReadMarkState(
      confirmedCursor: _confirmedCursor,
      presentedMessageIds: _presentedIds,
    );
  }

  Future<void> consider(ChatReadSighting sighting) async {
    if (!_register(sighting)) {
      return;
    }
    if (state.inFlight) {
      return;
    }
    final frontier = _frontier();
    if (frontier == null) {
      state = state.copyWith(clearCandidate: true);
      return;
    }
    if (!_shouldDispatch(frontier, sighting.trigger)) {
      return;
    }
    await _postFrontier(frontier);
  }

  bool _register(ChatReadSighting sighting) {
    if (!sighting.isEligible || sighting.roomId != arg) {
      return false;
    }
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return false;
    }
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated || auth.user.id != sighting.userId) {
      return false;
    }
    if (ref.read(chatRevokedRoomIdsProvider).contains(arg) || state.accessRevoked) {
      return false;
    }
    final history = ref.read(chatRoomHistoryControllerProvider(arg)).valueOrNull;
    final known = history?.timeline.byId[sighting.message.id];
    if (known == null || known.chatRoomId != arg) {
      return false;
    }
    _presentedIds = {..._presentedIds, sighting.message.id};
    state = state.copyWith(presentedMessageIds: _presentedIds);
    return true;
  }

  int? _frontier() {
    final history = ref.read(chatRoomHistoryControllerProvider(arg)).valueOrNull;
    final auth = ref.read(authControllerProvider);
    if (history == null || history.accessRevoked || auth is! AuthAuthenticated) {
      return null;
    }
    return computeSafeReadFrontier(
      timeline: history.timeline.messages,
      presentedIds: _presentedIds,
      userId: auth.user.id,
      roomId: arg,
      confirmedCursor: state.confirmedCursor,
      hasOlder: history.hasOlder,
      trustedMaxId: history.trustedMaxId,
    );
  }

  bool _shouldDispatch(int frontier, ChatReadTrigger trigger) {
    if (state.inFlight) {
      return false;
    }
    final confirmed = state.confirmedCursor;
    if (confirmed != null && frontier <= confirmed) {
      return false;
    }
    if (_unconfirmedAttemptId == frontier &&
        trigger != ChatReadTrigger.resume &&
        trigger != ChatReadTrigger.refresh &&
        trigger != ChatReadTrigger.scroll) {
      return false;
    }
    return true;
  }

  Future<void> _postFrontier(int frontier) async {
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return;
    }
    _keepAlive ??= ref.keepAlive();
    final generation = ++_generation;
    _unconfirmedAttemptId = frontier;
    state = state.copyWith(
      candidateCursor: frontier,
      inFlightCursor: frontier,
      clearFailure: true,
    );
    try {
      final result = await ref.read(chatRepositoryProvider).markRead(
            roomId: arg,
            lastReadMessageId: frontier,
          );
      if (!_stillCurrent(epoch, generation)) {
        _clearStaleInFlight(generation);
        return;
      }
      final confirmed = result.lastReadMessageId ?? frontier;
      _unconfirmedAttemptId = null;
      _confirmedCursor = confirmed;
      state = ChatReadMarkState(
        confirmedCursor: confirmed,
        presentedMessageIds: _presentedIds,
      );
      await ref.read(chatUnreadControllerProvider(arg).notifier).refresh();
      if (!_stillCurrent(epoch, generation)) {
        return;
      }
      final next = _frontier();
      if (next != null &&
          (state.confirmedCursor == null || next > state.confirmedCursor!) &&
          !state.inFlight) {
        await _postFrontier(next);
      }
    } on ApiForbiddenFailure catch (failure) {
      if (!_stillCurrent(epoch, generation)) {
        _clearStaleInFlight(generation);
        return;
      }
      revokeChatRoomAccess(ref, arg);
      state = ChatReadMarkState(
        accessRevoked: true,
        lastFailure: failure,
        presentedMessageIds: _presentedIds,
      );
    } on ApiSessionExpiredFailure catch (failure) {
      if (!_stillCurrent(epoch, generation)) {
        _clearStaleInFlight(generation);
        return;
      }
      _confirmedCursor = null;
      _presentedIds = {};
      state = ChatReadMarkState(lastFailure: failure);
    } on ApiFailure catch (failure) {
      if (!_stillCurrent(epoch, generation)) {
        _clearStaleInFlight(generation);
        return;
      }
      state = state.copyWith(
        lastFailure: failure,
        clearInFlight: true,
        clearCandidate: true,
      );
    } finally {
      if (!state.inFlight) {
        _keepAlive?.close();
        _keepAlive = null;
      }
    }
  }

  bool _stillCurrent(int epoch, int generation) {
    return neighborhoodSessionEpoch(ref) == epoch && generation == _generation;
  }

  void _clearStaleInFlight(int generation) {
    if (generation != _generation) {
      return;
    }
    try {
      state = state.copyWith(clearInFlight: true, clearCandidate: true);
    } on Object {
      return;
    }
  }
}

final chatReadCoordinatorProvider = NotifierProvider.autoDispose
    .family<ChatReadCoordinator, ChatReadMarkState, int>(
  ChatReadCoordinator.new,
);
