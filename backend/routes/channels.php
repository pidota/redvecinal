<?php

use App\Domains\Chat\Models\ChatRoom;
use App\Domains\Chat\Support\ChatMembershipGuard;
use Illuminate\Support\Facades\Broadcast;

Broadcast::channel('chat.room.{roomId}', function ($user, int $roomId) {
    $room = ChatRoom::query()->with('neighborhoodGroup')->find($roomId);
    if (! $room) {
        return false;
    }

    return app(ChatMembershipGuard::class)->canReadRoom($user, $room);
});
