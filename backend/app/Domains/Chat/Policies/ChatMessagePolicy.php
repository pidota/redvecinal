<?php

namespace App\Domains\Chat\Policies;

use App\Domains\Chat\Enums\ChatMessageStatus;
use App\Domains\Chat\Models\ChatMessage;
use App\Domains\Chat\Models\ChatRoom;
use App\Domains\Chat\Support\ChatMembershipGuard;
use App\Models\User;

class ChatMessagePolicy
{
    public function __construct(private readonly ChatMembershipGuard $guard) {}

    public function create(User $user, ChatRoom $room): bool
    {
        return $this->guard->canWriteRoom($user, $room);
    }

    public function view(User $user, ChatMessage $message): bool
    {
        $message->loadMissing('room.neighborhoodGroup');
        if (! $this->guard->canReadRoom($user, $message->room)) {
            return false;
        }

        if ($message->status === ChatMessageStatus::Visible) {
            return true;
        }

        if ($message->sender_id === $user->id) {
            return in_array($message->status, [ChatMessageStatus::Hidden, ChatMessageStatus::DeletedBySender], true);
        }

        return $this->guard->canModerateRoom($user, $message->room);
    }

    public function update(User $user, ChatMessage $message): bool
    {
        $message->loadMissing('room.neighborhoodGroup');

        return $message->sender_id === $user->id
            && $message->status === ChatMessageStatus::Visible
            && $this->guard->canWriteRoom($user, $message->room);
    }

    public function delete(User $user, ChatMessage $message): bool
    {
        return $this->update($user, $message);
    }

    public function hide(User $user, ChatMessage $message): bool
    {
        $message->loadMissing('room.neighborhoodGroup');

        if ($message->sender_id === $user->id) {
            return false;
        }

        return $this->guard->canModerateRoom($user, $message->room);
    }

    public function report(User $user, ChatMessage $message): bool
    {
        $message->loadMissing('room.neighborhoodGroup');

        return $this->guard->canReadRoom($user, $message->room)
            && $message->status === ChatMessageStatus::Visible;
    }

    public function viewReportedContent(User $user, ChatMessage $message): bool
    {
        if ($user->isSuperAdmin() && $user->can('chat.reports.resolve')) {
            return true;
        }

        return $user->can('chat.reports.view')
            && $user->isMunicipalAdministratorFor($message->municipality_id);
    }
}
