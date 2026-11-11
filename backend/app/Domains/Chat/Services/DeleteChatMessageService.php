<?php

namespace App\Domains\Chat\Services;

use App\Domains\Chat\Enums\ChatMessageStatus;
use App\Domains\Chat\Enums\ChatSyncEventType;
use App\Domains\Chat\Exceptions\ChatDomainException;
use App\Domains\Chat\Models\ChatMessage;
use App\Domains\Chat\Support\ChatMembershipGuard;
use App\Domains\Chat\Support\ChatMessageEventRecorder;
use App\Domains\Chat\Support\ChatSyncEventDispatcher;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;

class DeleteChatMessageService
{
    public function __construct(
        private readonly ChatMembershipGuard $guard,
        private readonly ChatMessageEventRecorder $recorder,
        private readonly ChatSyncEventDispatcher $sync,
    ) {}

    public function execute(ChatMessage $message, User $actor): ChatMessage
    {
        Gate::forUser($actor)->authorize('delete', $message);
        $message->loadMissing('room.neighborhoodGroup');
        $this->guard->assertCanWriteRoom($actor, $message->room);

        if ($message->sender_id !== $actor->id) {
            throw new ChatDomainException('Solo puede eliminar sus propios mensajes.');
        }

        if ($message->status !== ChatMessageStatus::Visible) {
            throw new ChatDomainException('El mensaje ya no está visible.');
        }

        return DB::transaction(function () use ($message, $actor) {
            $message = ChatMessage::query()->whereKey($message->id)->lockForUpdate()->firstOrFail();
            $from = $message->status->value;
            $message->update([
                'status' => ChatMessageStatus::DeletedBySender,
                'deleted_at' => now(),
                'version' => $message->version + 1,
            ]);

            $this->recorder->record($message, 'deleted_by_sender', $actor, $from, ChatMessageStatus::DeletedBySender->value);

            $this->sync->dispatch($message, ChatSyncEventType::MessageDeleted);

            return $message->fresh();
        });
    }
}
