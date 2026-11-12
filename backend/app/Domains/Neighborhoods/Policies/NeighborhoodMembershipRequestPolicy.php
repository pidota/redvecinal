<?php

namespace App\Domains\Neighborhoods\Policies;

use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Models\NeighborhoodMembershipRequest;
use App\Domains\Auth\Services\MobileApiAccessService;
use App\Domains\Neighborhoods\Support\NeighborhoodMunicipalityScope;
use App\Models\User;

class NeighborhoodMembershipRequestPolicy
{
    public function __construct(
        private readonly NeighborhoodMunicipalityScope $scope,
        private readonly MobileApiAccessService $mobileAccess,
    ) {}

    public function viewAny(User $user, NeighborhoodGroup $group): bool
    {
        return $this->canReviewMembershipRequests($user, $group);
    }

    public function view(User $user, NeighborhoodMembershipRequest $request): bool
    {
        if ($request->user_id === $user->id) {
            return true;
        }

        $group = $request->neighborhoodGroup;

        return $group !== null && $this->canReviewMembershipRequests($user, $group);
    }

    public function create(User $user, NeighborhoodGroup $group): bool
    {
        if (! $this->mobileAccess->mayObtainMobileToken($user)) {
            return false;
        }

        if (! $group->isAdministrable()) {
            return false;
        }

        return $this->scope->isMunicipalityAllowed($user, $group->municipality_id);
    }

    public function cancel(User $user, NeighborhoodMembershipRequest $request): bool
    {
        return $request->user_id === $user->id && $request->isPending();
    }

    public function approve(User $user, NeighborhoodMembershipRequest $request): bool
    {
        $group = $request->neighborhoodGroup;

        return $group !== null && $this->canReviewMembershipRequests($user, $group);
    }

    public function reject(User $user, NeighborhoodMembershipRequest $request): bool
    {
        $group = $request->neighborhoodGroup;

        return $group !== null && $this->canReviewMembershipRequests($user, $group);
    }

    /**
     * Misma regla que viewAny/approve/reject para solicitudes de incorporación.
     */
    public function canReviewMembershipRequests(User $user, NeighborhoodGroup $group): bool
    {
        return $this->canReview($user, $group);
    }

    private function canReview(User $user, NeighborhoodGroup $group): bool
    {
        if (! $group->isAdministrable()) {
            return false;
        }

        if ($user->isSuperAdmin()) {
            return true;
        }

        $membership = $user->groupMemberships()
            ->where('neighborhood_group_id', $group->id)
            ->where('status', MembershipStatus::Active)
            ->first();

        if ($membership?->membership_role === MembershipRole::President) {
            return true;
        }

        if ($membership?->membership_role === MembershipRole::Moderator) {
            return false;
        }

        return $user->can('group-members.approve')
            && $user->isMunicipalAdministratorFor($group->municipality_id);
    }
}
