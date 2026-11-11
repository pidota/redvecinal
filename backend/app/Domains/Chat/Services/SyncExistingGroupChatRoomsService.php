<?php

namespace App\Domains\Chat\Services;

use App\Domains\Neighborhoods\Models\NeighborhoodGroup;

class SyncExistingGroupChatRoomsService
{
    public function __construct(private readonly EnsureGroupChatRoomService $ensure) {}

    public function execute(): int
    {
        $count = 0;
        NeighborhoodGroup::query()->orderBy('id')->chunkById(100, function ($groups) use (&$count) {
            foreach ($groups as $group) {
                $this->ensure->execute($group);
                $count++;
            }
        });

        return $count;
    }
}
