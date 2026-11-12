<?php

namespace App\Domains\Neighborhoods\Support;

use App\Domains\Neighborhoods\Enums\MembershipRequestStatus;
use App\Domains\Neighborhoods\Exceptions\MembershipRequestException;
use App\Domains\Neighborhoods\Models\GroupMembershipEvent;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Models\NeighborhoodMembershipRequest;
use App\Models\User;
use Illuminate\Support\Carbon;

/**
 * Cooldown compartido: rechazo vía API (membership_requests) o vía panel (evento rejected en group_members).
 */
class MembershipRejectionCooldown
{
    public function assertUnlocked(NeighborhoodGroup $group, User $user): void
    {
        $cooldownDays = (int) config('red_vecinal.membership_requests.rejection_cooldown_days', 7);
        $latest = $this->latestRejectionAt($group, $user);

        if ($latest === null) {
            return;
        }

        $eligibleAt = $latest->copy()->addDays($cooldownDays);
        if (Carbon::now()->lt($eligibleAt)) {
            throw new MembershipRequestException(
                'Debes esperar '.$cooldownDays.' días desde el último rechazo antes de volver a solicitar.',
                422
            );
        }
    }

    public function latestRejectionAt(NeighborhoodGroup $group, User $user): ?Carbon
    {
        $apiRejectedAt = NeighborhoodMembershipRequest::query()
            ->where('neighborhood_group_id', $group->id)
            ->where('user_id', $user->id)
            ->where('status', MembershipRequestStatus::Rejected)
            ->whereNotNull('rejected_at')
            ->orderByDesc('rejected_at')
            ->lockForUpdate()
            ->value('rejected_at');

        $adminRejectedAt = GroupMembershipEvent::query()
            ->where('event', 'rejected')
            ->whereHas('groupMember', function ($query) use ($group, $user): void {
                $query->where('neighborhood_group_id', $group->id)
                    ->where('user_id', $user->id);
            })
            ->orderByDesc('created_at')
            ->lockForUpdate()
            ->value('created_at');

        $candidates = array_filter([
            $apiRejectedAt instanceof Carbon ? $apiRejectedAt : ($apiRejectedAt ? Carbon::parse($apiRejectedAt) : null),
            $adminRejectedAt instanceof Carbon ? $adminRejectedAt : ($adminRejectedAt ? Carbon::parse($adminRejectedAt) : null),
        ]);

        if ($candidates === []) {
            return null;
        }

        return collect($candidates)->max();
    }
}
