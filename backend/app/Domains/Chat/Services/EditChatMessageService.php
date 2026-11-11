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

class EditChatMessageService
{
    public function __construct(
        private readonly ChatMembershipGuard $guard,
        private readonly ChatMessageEventRecorder $recorder,
        private readonly ChatSyncEventDispatcher $sync,
    ) {}

    public function execute(ChatMessage $message, User $editor, string $body): ChatMessage
    {
        Gate::forUser($editor)->authorize('update', $message);
        $message->loadMissing('room.neighborhoodGroup');
        $this->guard->assertCanWriteRoom($editor, $message->room);

        if ($message->status !== ChatMessageStatus::Visible) {
            throw new ChatDomainException('No se puede editar este mensaje.');
        }

        $windowMinutes = (int) config('red_vecinal.chat.edit_window_minutes', 15);
        if ($message->created_at->diffInMinutes(now()) > $windowMinutes) {
            throw new ChatDomainException('La ventana de edición ha expirado.');
        }

        $body = trim($body);
        $maxLength = (int) config('red_vecinal.chat.max_message_length', 4000);
        if ($body === '' || mb_strlen($body) > $maxLength) {
            throw new \InvalidArgumentException('Mensaje inválido.');
        }

        return DB::transaction(function () use ($message, $editor, $body) {
            $message = ChatMessage::query()->whereKey($message->id)->lockForUpdate()->firstOrFail();
            $from = $message->body;
            $message->update([
                'body' => $body,
                'edited_at' => now(),
                'version' => $message->version + 1,
            ]);

            $this->recorder->record($message, 'edited', $editor, null, null, [
                'previous_length' => mb_strlen($from),
            ]);

            $this->sync->dispatch($message, ChatSyncEventType::MessageUpdated);

            return $message->fresh();
        });
    }
}
