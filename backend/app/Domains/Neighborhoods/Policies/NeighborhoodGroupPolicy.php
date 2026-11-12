<?php

namespace App\Domains\Neighborhoods\Policies;

use App\Domains\Auth\Services\MobileApiAccessService;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Support\NeighborhoodMunicipalityScope;
use App\Models\User;

class NeighborhoodGroupPolicy
{
    public function __construct(
        private readonly NeighborhoodMunicipalityScope $scope,
        private readonly MobileApiAccessService $mobileAccess,
    ) {}
    public function viewAny(User $user): bool
    {
        if ($user->can('neighborhood-groups.view')) {
            return true;
        }

        return $user->groupMemberships()
            ->where('status', MembershipStatus::Active)
            ->exists();
    }

    public function view(User $user, NeighborhoodGroup $group): bool
    {
        if ($user->groupMemberships()
            ->where('neighborhood_group_id', $group->id)
            ->where('status', MembershipStatus::Active)
            ->exists()) {
            return true;
        }

        if (! $user->can('neighborhood-groups.view')) {
            return false;
        }

        return $this->matchesMunicipalityScope($user, $group->municipality_id);
    }

    public function create(User $user): bool
    {
        return $user->can('neighborhood-groups.create');
    }

    public function update(User $user, NeighborhoodGroup $group): bool
    {
        if (! $group->isAdministrable() || ! $user->can('neighborhood-groups.update')) {
            return false;
        }

        return $this->matchesMunicipalityScope($user, $group->municipality_id);
    }

    public function delete(User $user, NeighborhoodGroup $group): bool
    {
        if (! $user->can('neighborhood-groups.delete')) {
            return false;
        }

        if ($group->activeMembers()->exists()) {
            return false;
        }

        return $this->matchesMunicipalityScope($user, $group->municipality_id);
    }

    public function manageMembers(User $user, NeighborhoodGroup $group): bool
    {
        return $this->update($user, $group)
            || ($group->isAdministrable() && $user->isActivePresidentOf($group));
    }

    /**
     * Vista descriptiva mínima para solicitar incorporación (sin membresía activa).
     */
    public function viewMembershipContext(User $user, NeighborhoodGroup $group): bool
    {
        if (! $this->mobileAccess->mayObtainMobileToken($user)) {
            return false;
        }

        if ($user->groupMemberships()
            ->where('neighborhood_group_id', $group->id)
            ->where('status', MembershipStatus::Active)
            ->exists()) {
            return true;
        }

        if (! $group->isAdministrable()) {
            return false;
        }

        return $this->scope->isMunicipalityAllowed($user, $group->municipality_id);
    }

    private function matchesMunicipalityScope(User $user, int $municipalityId): bool
    {
        if ($user->isSuperAdmin()) {
            return true;
        }

        return $user->isMunicipalAdministratorFor($municipalityId);
    }
}
