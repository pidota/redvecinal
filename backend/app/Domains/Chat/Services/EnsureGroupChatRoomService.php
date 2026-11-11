<?php

namespace App\Domains\Chat\Services;

use App\Domains\Chat\Enums\ChatRoomStatus;
use App\Domains\Chat\Enums\ChatRoomType;
use App\Domains\Chat\Models\ChatRoom;
use App\Domains\Neighborhoods\Enums\NeighborhoodGroupStatus;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use Illuminate\Support\Facades\DB;

class EnsureGroupChatRoomService
{
    public function execute(NeighborhoodGroup $group): ChatRoom
    {
        return DB::transaction(function () use ($group) {
            $existing = ChatRoom::query()
                ->where('neighborhood_group_id', $group->id)
                ->lockForUpdate()
                ->first();

            if ($existing) {
                return $existing;
            }

            $status = $group->status === NeighborhoodGroupStatus::Active
                ? ChatRoomStatus::Active
                : ChatRoomStatus::Locked;

            return ChatRoom::query()->create([
                'municipality_id' => $group->municipality_id,
                'neighborhood_group_id' => $group->id,
                'type' => ChatRoomType::GroupMain,
                'status' => $status,
            ]);
        });
    }

    public function syncRoomStatusForGroup(NeighborhoodGroup $group): void
    {
        $room = ChatRoom::query()->where('neighborhood_group_id', $group->id)->first();
        if (! $room) {
            return;
        }

        $status = $group->status === NeighborhoodGroupStatus::Active
            ? ChatRoomStatus::Active
            : ChatRoomStatus::Locked;

        if ($room->status !== $status) {
            $room->update(['status' => $status]);
        }
    }
}
