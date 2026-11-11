<?php

namespace App\Domains\Chat\Policies;

use App\Domains\Chat\Models\ChatRoom;
use App\Domains\Chat\Support\ChatMembershipGuard;
use App\Models\User;

class ChatRoomPolicy
{
    public function __construct(private readonly ChatMembershipGuard $guard) {}

    public function view(User $user, ChatRoom $room): bool
    {
        return $this->guard->canReadRoom($user, $room);
    }
}
