<?php

namespace App\Domains\Posts\Support;

use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Posts\Exceptions\PostDomainException;
use App\Domains\Posts\Models\Post;
use App\Models\User;

class PostMembershipGuard
{
    public function assertActiveGroupMember(User $user, NeighborhoodGroup $group): void
    {
        if (! $this->hasActiveMembership($user, $group)) {
            throw new PostDomainException('Se requiere membresía activa en la junta.');
        }
    }

    public function assertCanModerateGroup(User $user, NeighborhoodGroup $group): void
    {
        if (! $group->isAdministrable()) {
            throw new PostDomainException('La junta no admite moderación en su estado actual.');
        }

        $membership = $user->activeGroupMembershipFor($group);
        if (! $membership?->canPerformGroupAdministration()) {
            throw new PostDomainException('No tiene permiso para moderar publicaciones de esta junta.');
        }
    }

    public function assertNotSelfModeration(User $user, Post $post): void
    {
        if ($post->author_id === $user->id) {
            throw new PostDomainException('No puede moderar sus propias propuestas.');
        }
    }

    public function assertGroupAllowsPosting(NeighborhoodGroup $group): void
    {
        if (! $group->isAdministrable()) {
            throw new PostDomainException('La junta no admite nuevas publicaciones en su estado actual.');
        }
    }

    public function hasActiveMembership(User $user, NeighborhoodGroup $group): bool
    {
        return $user->groupMemberships()
            ->where('neighborhood_group_id', $group->id)
            ->where('status', MembershipStatus::Active)
            ->exists();
    }
}
