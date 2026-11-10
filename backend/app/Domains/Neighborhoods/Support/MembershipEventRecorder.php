<?php

namespace App\Domains\Neighborhoods\Support;

use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\GroupMembershipEvent;
use App\Models\User;

class MembershipEventRecorder
{
    public function record(GroupMember $member, string $event, ?User $actor = null, array $payload = []): GroupMembershipEvent
    {
        return GroupMembershipEvent::query()->create([
            'group_member_id' => $member->id,
            'actor_user_id' => $actor?->id,
            'event' => $event,
            'payload' => $payload,
            'created_at' => now(),
        ]);
    }
}
