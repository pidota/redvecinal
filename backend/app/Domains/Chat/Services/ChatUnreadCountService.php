<?php

namespace App\Domains\Chat\Services;

use App\Domains\Chat\Enums\ChatMessageStatus;
use App\Domains\Chat\Models\ChatMessage;
use App\Domains\Chat\Models\ChatReadState;
use App\Domains\Chat\Models\ChatRoom;
use App\Domains\Chat\Support\ChatMembershipGuard;
use App\Models\User;

class ChatUnreadCountService
{
    public function __construct(private readonly ChatMembershipGuard $guard) {}

    public function count(ChatRoom $room, User $user): int
    {
        $this->guard->assertCanReadRoom($user, $room);

        $lastReadId = ChatReadState::query()
            ->where('chat_room_id', $room->id)
            ->where('user_id', $user->id)
            ->value('last_read_message_id') ?? 0;

        return ChatMessage::query()
            ->where('chat_room_id', $room->id)
            ->where('status', ChatMessageStatus::Visible)
            ->where('sender_id', '!=', $user->id)
            ->where('id', '>', $lastReadId)
            ->count();
    }
}
