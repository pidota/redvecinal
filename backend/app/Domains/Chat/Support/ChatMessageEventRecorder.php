<?php

namespace App\Domains\Chat\Support;

use App\Domains\Chat\Models\ChatMessage;
use App\Domains\Chat\Models\ChatMessageEvent;
use App\Models\User;

class ChatMessageEventRecorder
{
    public function record(
        ChatMessage $message,
        string $event,
        ?User $actor = null,
        ?string $fromStatus = null,
        ?string $toStatus = null,
        array $payload = [],
    ): ChatMessageEvent {
        return ChatMessageEvent::query()->create([
            'municipality_id' => $message->municipality_id,
            'chat_message_id' => $message->id,
            'chat_room_id' => $message->chat_room_id,
            'actor_user_id' => $actor?->id,
            'event' => $event,
            'from_status' => $fromStatus,
            'to_status' => $toStatus,
            'payload' => $payload === [] ? null : $payload,
            'created_at' => now(),
        ]);
    }
}
