<?php

namespace App\Domains\Chat\Support;

use App\Domains\Chat\Exceptions\ChatDomainException;
use App\Domains\Chat\Models\ChatRoom;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Models\User;

class ChatMembershipGuard
{
    public function assertCanReadRoom(User $user, ChatRoom $room): void
    {
        if (! $this->canReadRoom($user, $room)) {
            throw new ChatDomainException('No tiene acceso a esta sala de chat.');
        }
    }

    public function canReadRoom(User $user, ChatRoom $room): bool
    {
        $group = $room->neighborhoodGroup;
        if (! $group) {
            return false;
        }

        return $this->hasActiveMembership($user, $group);
    }

    public function assertCanWriteRoom(User $user, ChatRoom $room): void
    {
        if (! $this->canWriteRoom($user, $room)) {
            throw new ChatDomainException('No puede enviar mensajes en esta sala.');
        }
    }

    public function canWriteRoom(User $user, ChatRoom $room): bool
    {
        if (! $room->isWritable()) {
            return false;
        }

        return $this->hasActiveMembership($user, $room->neighborhoodGroup);
    }

    public function assertCanModerateRoom(User $user, ChatRoom $room): void
    {
        if (! $this->canModerateRoom($user, $room)) {
            throw new ChatDomainException('No puede moderar mensajes en esta sala.');
        }
    }

    public function canModerateRoom(User $user, ChatRoom $room): bool
    {
        $group = $room->neighborhoodGroup;
        if (! $group?->isAdministrable()) {
            return false;
        }

        $membership = $user->activeGroupMembershipFor($group);

        return $membership?->canPerformGroupAdministration() === true;
    }

    public function hasActiveMembership(User $user, NeighborhoodGroup $group): bool
    {
        return $user->groupMemberships()
            ->where('neighborhood_group_id', $group->id)
            ->where('status', MembershipStatus::Active)
            ->exists();
    }
}
