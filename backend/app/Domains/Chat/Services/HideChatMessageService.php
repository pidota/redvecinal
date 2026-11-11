<?php

namespace App\Domains\Chat\Services;

use App\Domains\Chat\Enums\ChatMessageStatus;
use App\Domains\Chat\Enums\ChatSyncEventType;
use App\Domains\Chat\Exceptions\ChatDomainException;
use App\Domains\Chat\Models\ChatMessage;
use App\Domains\Chat\Support\ChatMessageEventRecorder;
use App\Domains\Chat\Support\ChatSyncEventDispatcher;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;

class HideChatMessageService
{
    public function __construct(
        private readonly ChatMessageEventRecorder $recorder,
        private readonly ChatSyncEventDispatcher $sync,
    ) {}

    public function execute(ChatMessage $message, User $moderator, ?string $reason = null): ChatMessage
    {
        Gate::forUser($moderator)->authorize('hide', $message);

        if ($message->sender_id === $moderator->id) {
            throw new ChatDomainException('Use eliminación lógica para sus propios mensajes.');
        }

        if ($message->status !== ChatMessageStatus::Visible) {
            throw new ChatDomainException('Solo se pueden ocultar mensajes visibles.');
        }

        return DB::transaction(function () use ($message, $moderator, $reason) {
            $message = ChatMessage::query()->whereKey($message->id)->lockForUpdate()->firstOrFail();
            $from = $message->status->value;
            $message->update([
                'status' => ChatMessageStatus::Hidden,
                'version' => $message->version + 1,
            ]);

            $this->recorder->record($message, 'hidden', $moderator, $from, ChatMessageStatus::Hidden->value, [
                'reason' => $reason,
            ]);

            $this->sync->dispatch($message, ChatSyncEventType::MessageModerated);

            return $message->fresh();
        });
    }
}
