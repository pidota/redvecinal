<?php

namespace App\Domains\Neighborhoods\Support;

use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodMembershipRequest;

/**
 * Orden global para el par (junta, usuario): membership_requests → group_members.
 */
final class GroupUserMembershipLocks
{
    public static function lockMembershipRequestsForPair(int $neighborhoodGroupId, int $userId): void
    {
        NeighborhoodMembershipRequest::query()
            ->where('neighborhood_group_id', $neighborhoodGroupId)
            ->where('user_id', $userId)
            ->orderBy('id')
            ->lockForUpdate()
            ->get();
    }

    public static function lockGroupMemberForPair(int $neighborhoodGroupId, int $userId): ?GroupMember
    {
        return GroupMember::query()
            ->where('neighborhood_group_id', $neighborhoodGroupId)
            ->where('user_id', $userId)
            ->lockForUpdate()
            ->first();
    }

    public static function lockGroupMemberById(int $groupMemberId): GroupMember
    {
        return GroupMember::query()->whereKey($groupMemberId)->lockForUpdate()->firstOrFail();
    }
}
