import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_failure.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import '../../neighborhoods/application/neighborhood_session.dart';
import '../data/chat_client_message_id.dart';
import '../data/chat_repository.dart';
import '../data/chat_uncertain_store.dart';
import '../data/models/chat_enums.dart';
import '../data/models/chat_message.dart';
import 'chat_access.dart';
import 'chat_outgoing.dart';

class ChatSendCoordinator extends Notifier<ChatSendState> {
  ChatSendCoordinator({String Function()? uuidV4})
      : _uuidV4 = uuidV4 ?? generateChatClientMessageId;

  final String Function() _uuidV4;
  final Map<String, Future<ChatOutgoingMessage>> _inFlight = {};
  Future<void>? _hydrateFuture;

  @override
  ChatSendState build() {
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (next is! AuthAuthenticated) {
        _hydrateFuture = null;
        state = const ChatSendState(hydrated: true);
      }
    });
    return const ChatSendState();
  }

  Future<void> ensureHydrated() {
    if (state.hydrated && _hydrateFuture != null) {
      return _hydrateFuture!;
    }
    final future = _hydrate();
    _hydrateFuture = future;
    return future;
  }

  Future<void> _hydrate() async {
    try {
      final loaded = await ref.read(chatUncertainStoreProvider).loadAll();
      final mapped = <String, ChatOutgoingMessage>{};
      for (final record in loaded) {
        mapped[record.storageKey] = ChatOutgoingMessage(
          userId: record.userId,
          roomId: record.roomId,
          body: record.body,
          clientMessageId: record.clientMessageId,
          status: ChatOutgoingStatus.uncertain,
        );
      }
      state = ChatSendState(messages: mapped, hydrated: true);
    } on Object {
      state = const ChatSendState(hydrated: true);
    }
  }

  Future<ChatOutgoingMessage?> submit({
    required int roomId,
    required String rawBody,
  }) async {
    await ensureHydrated();
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated) {
      return null;
    }
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return null;
    }

    final body = rawBody.trim();
    if (body.isEmpty || body.length > ChatRepository.maxBodyLength) {
      return ChatOutgoingMessage(
        userId: auth.user.id,
        roomId: roomId,
        body: body,
        clientMessageId: '',
        status: ChatOutgoingStatus.failedBeforeDispatch,
        failure: const ApiValidationFailure(
          {
            'body': ['Mensaje inválido.'],
          },
          'Mensaje inválido.',
        ),
      );
    }

    final lock = '${auth.user.id}|$roomId';
    final pending = _inFlight[lock];
    if (pending != null) {
      return pending;
    }

    late final Future<ChatOutgoingMessage> future;
    future = _sendLocked(
      ChatOutgoingMessage(
        userId: auth.user.id,
        roomId: roomId,
        body: body,
        clientMessageId: _uuidV4(),
        status: ChatOutgoingStatus.sending,
      ),
      epoch,
    );
    _inFlight[lock] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(lock);
    }
  }

  Future<ChatOutgoingMessage?> retry(String key) async {
    await ensureHydrated();
    final existing = state.messages[key];
    if (existing == null || !isChatSendRetryable(existing)) {
      return existing;
    }
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return null;
    }
    final lock = '${existing.userId}|${existing.roomId}';
    final pending = _inFlight[lock];
    if (pending != null) {
      return pending;
    }
    late final Future<ChatOutgoingMessage> future;
    future = _sendLocked(
      existing.copyWith(status: ChatOutgoingStatus.sending, clearFailure: true),
      epoch,
    );
    _inFlight[lock] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(lock);
    }
  }

  Future<ChatOutgoingMessage?> reconcile({
    required int roomId,
    required String clientMessageId,
  }) async {
    final epoch = neighborhoodSessionEpoch(ref);
    if (epoch == null) {
      return null;
    }
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated) {
      return null;
    }
    final key = '${auth.user.id}|$roomId|$clientMessageId';
    final current = state.messages[key];
    if (current == null) {
      return null;
    }

    try {
      final page = await ref.read(chatRepositoryProvider).listMessages(
            roomId: roomId,
            limit: ChatRepository.maxLimit,
          );
      if (neighborhoodSessionEpoch(ref) != epoch) {
        return current;
      }
      ChatMessage? match;
      for (final message in page.messages) {
        if (message.clientMessageId == clientMessageId &&
            message.senderId == auth.user.id) {
          match = message;
          break;
        }
      }
      if (match == null) {
        return current;
      }
      final confirmed = current.copyWith(
        status: ChatOutgoingStatus.confirmed,
        confirmed: match,
        clearFailure: true,
      );
      _put(confirmed);
      await _persist();
      return confirmed;
    } on ApiFailure {
      return current;
    }
  }

  Future<ChatOutgoingMessage> _sendLocked(
    ChatOutgoingMessage outgoing,
    int epoch,
  ) async {
    _put(outgoing);
    await _persist();
    try {
      final result = await ref.read(chatRepositoryProvider).sendMessage(
            roomId: outgoing.roomId,
            body: outgoing.body,
            clientMessageId: outgoing.clientMessageId,
          );
      if (neighborhoodSessionEpoch(ref) != epoch) {
        return outgoing;
      }
      final confirmed = outgoing.copyWith(
        status: ChatOutgoingStatus.confirmed,
        confirmed: result.message,
        clearFailure: true,
      );
      _put(confirmed);
      await _persist();
      return confirmed;
    } catch (failure) {
      if (neighborhoodSessionEpoch(ref) != epoch) {
        return outgoing;
      }
      if (failure is ApiForbiddenFailure) {
        revokeChatRoomAccess(ref, outgoing.roomId);
        _remove(outgoing.key);
        await _persist();
        return outgoing.copyWith(
          status: ChatOutgoingStatus.failedBeforeDispatch,
          failure: failure,
        );
      }
      final mapped = failure is ApiFailure ? failure : const ApiUnexpectedFailure();
      final next = outgoing.copyWith(
        status: isChatSendUncertain(failure)
            ? ChatOutgoingStatus.uncertain
            : ChatOutgoingStatus.failedBeforeDispatch,
        failure: mapped,
      );
      _put(next);
      await _persist();
      return next;
    }
  }

  void _put(ChatOutgoingMessage message) {
    final next = Map<String, ChatOutgoingMessage>.from(state.messages);
    next[message.key] = message;
    state = ChatSendState(messages: next, hydrated: true);
  }

  void _remove(String key) {
    final next = Map<String, ChatOutgoingMessage>.from(state.messages)
      ..remove(key);
    state = ChatSendState(messages: next, hydrated: true);
  }

  Future<void> _persist() async {
    final persistable = state.messages.values
        .where(
          (item) =>
              item.status == ChatOutgoingStatus.uncertain ||
              item.status == ChatOutgoingStatus.sending,
        )
        .map(
          (item) => ChatUncertainRecord(
            userId: item.userId,
            roomId: item.roomId,
            clientMessageId: item.clientMessageId,
            body: item.body,
            status: ChatOutgoingStatus.uncertain,
            updatedAt: DateTime.now(),
          ),
        )
        .toList();
    await ref.read(chatUncertainStoreProvider).saveAll(
          boundChatUncertainRecords(persistable),
        );
  }
}

final chatSendCoordinatorProvider =
    NotifierProvider<ChatSendCoordinator, ChatSendState>(ChatSendCoordinator.new);
