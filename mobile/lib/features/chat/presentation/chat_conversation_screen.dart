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
import '../application/chat_read_coordinator.dart';
import '../application/chat_room_history_controller.dart';
import '../application/chat_rooms_controller.dart';
import '../application/chat_route_observer.dart';
import '../application/chat_send_coordinator.dart';
import '../data/models/chat_enums.dart';
import '../data/models/chat_message.dart';
import '../data/models/chat_room.dart';
import 'chat_labels.dart';
import 'chat_thread.dart';
import 'widgets/chat_composer.dart';
import 'widgets/chat_message_bubble.dart';
import 'widgets/chat_visible_message.dart';

class ChatConversationScreen extends ConsumerStatefulWidget {
  const ChatConversationScreen({required this.roomId, super.key});

  final int roomId;

  @override
  ConsumerState<ChatConversationScreen> createState() =>
      _ChatConversationScreenState();
}

class _ChatConversationScreenState
    extends ConsumerState<ChatConversationScreen>
    with WidgetsBindingObserver, RouteAware {
  final _composer = TextEditingController();
  final _scroll = ScrollController();
  var _appResumed = true;
  var _routeCurrent = true;
  var _visibilityGeneration = 0;
  var _readTrigger = ChatReadTrigger.layout;
  RouteObserver<ModalRoute<void>>? _routeObserver;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _composer.addListener(() => setState(() {}));
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatSendCoordinatorProvider.notifier).ensureHydrated();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    _routeObserver?.unsubscribe(this);
    _routeObserver = ref.read(chatRouteObserverProvider);
    if (route is PageRoute) {
      _routeObserver!.subscribe(this, route);
    }
    _routeCurrent = route?.isCurrent ?? false;
  }

  @override
  void dispose() {
    _routeObserver?.unsubscribe(this);
    WidgetsBinding.instance.removeObserver(this);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _composer.dispose();
    super.dispose();
  }

  @override
  void didPush() {
    _routeCurrent = true;
  }

  @override
  void didPop() {
    _routeCurrent = false;
  }

  @override
  void didPushNext() {
    _routeCurrent = false;
  }

  @override
  void didPopNext() {
    _routeCurrent = true;
    _scheduleReadPass(ChatReadTrigger.route);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    _appResumed = resumed;
    if (resumed) {
      _scheduleReadPass(ChatReadTrigger.resume);
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) {
      return;
    }
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 64) {
      ref.read(chatRoomHistoryControllerProvider(widget.roomId).notifier).loadOlder();
    }
  }

  void _scheduleReadPass(ChatReadTrigger trigger) {
    _readTrigger = trigger;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      setState(() => _visibilityGeneration++);
    });
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
    ref.watch(chatReadCoordinatorProvider(roomId));

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

    ref.listen(chatReadCoordinatorProvider(roomId), (previous, next) {
      if (previous?.inFlight == true && !next.inFlight && _routeCurrent && _appResumed) {
        _scheduleReadPass(ChatReadTrigger.layout);
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
              onPressed: () async {
                await ref
                    .read(chatRoomHistoryControllerProvider(roomId).notifier)
                    .refreshNewer();
                _scheduleReadPass(ChatReadTrigger.refresh);
              },
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
              child: NotificationListener<ScrollEndNotification>(
                onNotification: (_) {
                  _scheduleReadPass(ChatReadTrigger.scroll);
                  return false;
                },
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
    final bubble = ChatMessageBubble(
      message: message,
      outgoing: outgoing,
      isMine: isMine,
      onRetry: retryable == null
          ? null
          : () => ref.read(chatSendCoordinatorProvider.notifier).retry(retryable.key),
    );
    if (message == null || message.chatRoomId != widget.roomId) {
      return bubble;
    }
    return ChatVisibleMessage(
      message: message,
      generation: _visibilityGeneration,
      onPresented: _onMessagePresented,
      child: bubble,
    );
  }

  void _onMessagePresented(ChatMessage message) {
    final auth = ref.read(authControllerProvider);
    if (auth is! AuthAuthenticated) {
      return;
    }
    if (!_appResumed || !_routeCurrent || !mounted) {
      return;
    }
    ref.read(chatReadCoordinatorProvider(widget.roomId).notifier).consider(
          ChatReadSighting(
            roomId: widget.roomId,
            userId: auth.user.id,
            message: message,
            appResumed: _appResumed,
            routeCurrent: _routeCurrent,
            trigger: _readTrigger,
          ),
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
      _scheduleReadPass(ChatReadTrigger.layout);
    }
  }
}
