<?php

namespace App\Domains\Neighborhoods\Policies;

use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Models\User;

class GroupMemberPolicy
{
    public function viewAny(User $user): bool
    {
        return $user->can('group-members.view');
    }

    public function view(User $user, GroupMember $member): bool
    {
        $group = $member->neighborhoodGroup;

        if (! $group) {
            return false;
        }

        if ($this->isActiveMember($user, $group)) {
            return true;
        }

        if (! $user->can('group-members.view')) {
            return false;
        }

        return $this->isMunicipalOperator($user, $group);
    }

    public function create(User $user, NeighborhoodGroup $group): bool
    {
        if (! $group->isAdministrable()) {
            return false;
        }

        if ($this->isMunicipalOperator($user, $group)) {
            return $user->can('group-members.create');
        }

        return $user->isActivePresidentOf($group);
    }

    public function approve(User $user, GroupMember $member): bool
    {
        return $this->moderateMembership($user, $member, 'group-members.approve');
    }

    public function reject(User $user, GroupMember $member): bool
    {
        return $this->moderateMembership($user, $member, 'group-members.approve');
    }

    public function suspend(User $user, GroupMember $member): bool
    {
        return $this->moderateMembership($user, $member, 'group-members.suspend');
    }

    public function remove(User $user, GroupMember $member): bool
    {
        return $this->moderateMembership($user, $member, 'group-members.update');
    }

    public function assignPresident(User $user, GroupMember $member): bool
    {
        $group = $member->neighborhoodGroup;

        if (! $group?->isAdministrable()) {
            return false;
        }

        if ($user->isActivePresidentOf($group)) {
            return false;
        }

        if ($member->status !== MembershipStatus::Active) {
            return false;
        }

        if (! $user->can('group-presidents.assign')) {
            return false;
        }

        return $this->isMunicipalOperator($user, $group);
    }

  public function changeOwnRole(User $user, GroupMember $member): bool
    {
        return $user->id !== $member->user_id;
    }

    private function moderateMembership(User $user, GroupMember $member, string $permission): bool
    {
        $group = $member->neighborhoodGroup;

        if (! $group?->isAdministrable() || ! $user->can($permission)) {
            return false;
        }

        if ($user->isActivePresidentOf($group)) {
            return false;
        }

        $ownMembership = $user->activeGroupMembershipFor($group);
        if ($ownMembership?->membership_role === MembershipRole::Moderator) {
            return false;
        }

        return $this->isMunicipalOperator($user, $group);
    }

    private function isMunicipalOperator(User $user, NeighborhoodGroup $group): bool
    {
        if ($user->isSuperAdmin()) {
            return true;
        }

        return $user->isMunicipalAdministratorFor($group->municipality_id);
    }

    private function isActiveMember(User $user, NeighborhoodGroup $group): bool
    {
        return $user->groupMemberships()
            ->where('neighborhood_group_id', $group->id)
            ->where('status', MembershipStatus::Active)
            ->exists();
    }
}
