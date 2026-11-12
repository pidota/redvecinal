<?php

namespace App\Domains\Neighborhoods\Support;

use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Models\User;
use Illuminate\Support\Collection;

class NeighborhoodMunicipalityScope
{
    public function allowedMunicipalityIds(User $user): Collection
    {
        if ($user->isSuperAdmin()) {
            return NeighborhoodGroup::query()->distinct()->pluck('municipality_id');
        }

        return $user->activeMunicipalityMemberships()
            ->pluck('municipality_id')
            ->merge(
                $user->groupMemberships()
                    ->where('status', MembershipStatus::Active)
                    ->pluck('municipality_id')
            )
            ->unique()
            ->values();
    }

    public function isMunicipalityAllowed(User $user, int $municipalityId): bool
    {
        return $this->allowedMunicipalityIds($user)->contains($municipalityId);
    }
}
