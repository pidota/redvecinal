<?php

namespace App\Domains\Chat\Support;

use App\Domains\Chat\Enums\ChatSyncEventType;
use App\Domains\Chat\Events\ChatRoomSyncBroadcast;
use App\Domains\Chat\Models\ChatMessage;

/**
 * Emite sincronización WebSocket dentro de la transacción del dominio.
 * El evento usa {@see ChatRoomSyncBroadcast::$afterCommit} como único mecanismo post-commit.
 */
final class ChatSyncEventDispatcher
{
    public function dispatch(ChatMessage $message, ChatSyncEventType $type): void
    {
        event(new ChatRoomSyncBroadcast($message->fresh(), $type));
    }
}
