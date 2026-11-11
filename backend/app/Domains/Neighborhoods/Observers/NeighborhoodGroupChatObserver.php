<?php

namespace App\Domains\Neighborhoods\Observers;

use App\Domains\Chat\Services\EnsureGroupChatRoomService;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;

class NeighborhoodGroupChatObserver
{
    public function __construct(private readonly EnsureGroupChatRoomService $ensure) {}

    public function updated(NeighborhoodGroup $group): void
    {
        if ($group->wasChanged('status')) {
            $this->ensure->syncRoomStatusForGroup($group);
        }
    }
}
