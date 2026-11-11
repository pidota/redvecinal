<?php

namespace Tests\Concerns;

use App\Domains\Chat\Models\ChatRoom;
use App\Domains\Chat\Services\EnsureGroupChatRoomService;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;

trait CreatesChatFixtures
{
    protected function chatRoomForGroup(NeighborhoodGroup $group): ChatRoom
    {
        return app(EnsureGroupChatRoomService::class)->execute($group);
    }
}
