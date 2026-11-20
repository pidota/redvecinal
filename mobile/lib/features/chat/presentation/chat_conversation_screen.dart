import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_failure.dart';
import '../../../core/theme/rv_spacing.dart';
import '../../../shared/widgets/rv_empty_state.dart';
import '../../../shared/widgets/rv_loading_indicator.dart';
import '../../../shared/widgets/rv_primary_button.dart';
import '../../auth/application/auth_controller.dart';
import '../../auth/domain/auth_state.dart';
import '../application/chat_access.dart';
import '../application/chat_outgoing.dart';
import '../application/chat_room_history_controller.dart';
import '../application/chat_rooms_controller.dart';
import '../application/chat_send_coordinator.dart';
import '../data/models/chat_enums.dart';
import '../data/models/chat_room.dart';
import 'chat_labels.dart';
import 'chat_thread.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_message_bubble.dart';

class ChatConversationScreen extends ConsumerStatefulWidget {
  const ChatConversationScreen({required this.roomId, super.key});

  final int roomId;

  @override
  ConsumerState<ChatConversationScreen> createState() =>
      _ChatConversationScreenState();
}

class _ChatConversationScreenState
    extends ConsumerState<ChatConversationScreen> {
  final _composer = TextEditingController();
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _composer.addListener(() => setState(() {}));
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatSendCoordinatorProvider.notifier).ensureHydrated();
    });
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _composer.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 64) {
      ref.read(chatRoomHistoryControllerProvider(widget.roomId).notifier).loadOlder();
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomId = widget.roomId;
    final auth = ref.watch(authControllerProvider);
    final userId = auth is AuthAuthenticated ? auth.user.id : null;
    final revoked = ref.watch(chatRevokedRoomIdsProvider).contains(roomId);
    final rooms = ref.watch(chatRoomsControllerProvider).valueOrNull ?? const <ChatRoom>[];
    final room = rooms.where((item) => item.id == roomId).firstOrNull;
    final historyAsync = ref.watch(chatRoomHistoryControllerProvider(roomId));
    final sendState = ref.watch(chatSendCoordinatorProvider);

    ref.listen(chatSendCoordinatorProvider, (_, next) {
      if (userId == null) {
        return;
      }
      for (final item in next.forRoom(userId: userId, roomId: roomId)) {
        final confirmed = item.confirmed;
        if (item.status == ChatOutgoingStatus.confirmed && confirmed != null) {
          ref
              .read(chatRoomHistoryControllerProvider(roomId).notifier)
              .ingestConfirmed(confirmed);
        }
      }
    });

    final title = room != null ? chatRoomTitle(room) : 'Sala $roomId';
    final writable = room?.status.isWritable ?? false;
    final accessRevoked = revoked ||
        (historyAsync.valueOrNull?.accessRevoked ?? false);

    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: BackButton(
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: [
          if (!accessRevoked)
            IconButton(
              tooltip: 'Actualizar mensajes',
              onPressed: () => ref
                  .read(chatRoomHistoryControllerProvider(roomId).notifier)
                  .refreshNewer(),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: SafeArea(
        child: accessRevoked
            ? RvEmptyState(
                title: 'Acceso revocado',
                message:
                    'Ya no tienes acceso a esta conversación. El historial no se muestra.',
                icon: Icons.lock_outline,
                action: TextButton(
                  onPressed: () => context.pop(),
                  child: const Text('Volver al listado'),
                ),
              )
            : Column(
                children: [
                  if (room != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        RvSpacing.md,
                        RvSpacing.sm,
                        RvSpacing.md,
                        0,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Sala ${room.id} · ${chatRoomStatusLabel(room)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ),
                  Expanded(child: _historyBody(historyAsync, sendState, userId)),
                  ChatComposer(
                    controller: _composer,
                    enabled: userId != null && writable,
                    canSend: userId != null &&
                        writable &&
                        _composer.text.trim().isNotEmpty,
                    sending: _isSending(sendState, userId),
                    onSend: _submit,
                    readOnlyReason: userId == null
                        ? 'Inicia sesión para participar.'
                        : writable
                            ? null
                            : 'Esta conversación está en modo lectura.',
                  ),
                ],
              ),
      ),
    );
  }

  Widget _historyBody(
    AsyncValue<ChatRoomHistoryState> historyAsync,
    ChatSendState sendState,
    int? userId,
  ) {
    return historyAsync.when(
      loading: () => const RvLoadingIndicator(message: 'Cargando mensajes'),
      error: (error, _) => RvEmptyState(
        title: 'No pudimos cargar el historial',
        message: error is ApiFailure
            ? error.userMessage
            : const ApiUnexpectedFailure().userMessage,
        icon: Icons.cloud_off_outlined,
        action: RvPrimaryButton(
          label: 'Reintentar',
          icon: Icons.refresh,
          onPressed: () => ref
              .read(chatRoomHistoryControllerProvider(widget.roomId).notifier)
              .refresh(),
        ),
      ),
      data: (history) {
        if (history.accessRevoked) {
          return const SizedBox.shrink();
        }
        final outgoing = userId == null
            ? const <ChatOutgoingMessage>[]
            : sendState.forRoom(userId: userId, roomId: widget.roomId);
        final items = buildChatThreadItems(
          timeline: history.timeline,
          outgoing: outgoing,
        );
        if (items.isEmpty) {
          return const RvEmptyState(
            title: 'Sin mensajes',
            message: 'Todavía no hay mensajes en esta sala.',
            icon: Icons.chat_bubble_outline,
          );
        }

        return Column(
          children: [
            if (history.isLoadingOlder || history.isRefreshingNewer)
              const LinearProgressIndicator(minHeight: 2),
            if (history.hasOlder)
              TextButton(
                onPressed: history.isLoadingOlder
                    ? null
                    : () => ref
                        .read(
                          chatRoomHistoryControllerProvider(widget.roomId)
                              .notifier,
                        )
                        .loadOlder(),
                child: Text(
                  history.isLoadingOlder
                      ? 'Cargando anteriores'
                      : 'Cargar mensajes anteriores',
                ),
              ),
            Expanded(
              child: ListView.builder(
                controller: _scroll,
                reverse: true,
                padding: const EdgeInsets.all(RvSpacing.md),
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final item = items[items.length - 1 - index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: RvSpacing.sm),
                    child: _bubbleFor(item, userId),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _bubbleFor(ChatThreadItem item, int? userId) {
    final outgoing = item.outgoing;
    final message = item.message;
    final isMine = outgoing != null
        ? outgoing.userId == userId
        : message?.senderId == userId;
    final retryable =
        outgoing != null && isChatSendRetryable(outgoing) ? outgoing : null;
    return ChatMessageBubble(
      message: message,
      outgoing: outgoing,
      isMine: isMine,
      onRetry: retryable == null
          ? null
          : () => ref.read(chatSendCoordinatorProvider.notifier).retry(retryable.key),
    );
  }

  bool _isSending(ChatSendState sendState, int? userId) {
    if (userId == null) {
      return false;
    }
    return sendState
        .forRoom(userId: userId, roomId: widget.roomId)
        .any((item) => item.status == ChatOutgoingStatus.sending);
  }

  Future<void> _submit() async {
    final body = _composer.text;
    final result = await ref.read(chatSendCoordinatorProvider.notifier).submit(
          roomId: widget.roomId,
          rawBody: body,
        );
    if (result == null) {
      return;
    }
    if (result.status == ChatOutgoingStatus.failedBeforeDispatch &&
        result.clientMessageId.isEmpty) {
      return;
    }
    if (result.status == ChatOutgoingStatus.confirmed ||
        result.status == ChatOutgoingStatus.sending ||
        result.status == ChatOutgoingStatus.uncertain) {
      _composer.clear();
    }
    final confirmed = result.confirmed;
    if (confirmed != null) {
      ref
          .read(chatRoomHistoryControllerProvider(widget.roomId).notifier)
          .ingestConfirmed(confirmed);
    }
  }
}
