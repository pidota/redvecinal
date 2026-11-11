<?php

namespace App\Domains\Chat\Services;

use App\Domains\Chat\Enums\ChatMessageStatus;
use App\Domains\Chat\Enums\ChatSyncEventType;
use App\Domains\Chat\Models\ChatMessage;
use App\Domains\Chat\Models\ChatRoom;
use App\Domains\Chat\Support\ChatMembershipGuard;
use App\Domains\Chat\Support\ChatMessageEventRecorder;
use App\Domains\Chat\Support\ChatSyncEventDispatcher;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Str;

class SendChatMessageService
{
    public function __construct(
        private readonly ChatMembershipGuard $guard,
        private readonly ChatMessageEventRecorder $recorder,
        private readonly ChatSyncEventDispatcher $sync,
    ) {}

    public function execute(ChatRoom $room, User $sender, string $body, ?string $clientMessageId = null): ChatMessage
    {
        $this->guard->assertCanWriteRoom($sender, $room);

        $body = trim($body);
        $maxLength = (int) config('red_vecinal.chat.max_message_length', 4000);
        if ($body === '' || mb_strlen($body) > $maxLength) {
            throw new \InvalidArgumentException('Mensaje inválido.');
        }

        if ($clientMessageId !== null && ! Str::isUuid($clientMessageId)) {
            throw new \InvalidArgumentException('client_message_id inválido.');
        }

        return DB::transaction(function () use ($room, $sender, $body, $clientMessageId) {
            if ($clientMessageId) {
                $existing = ChatMessage::query()
                    ->where('chat_room_id', $room->id)
                    ->where('sender_id', $sender->id)
                    ->where('client_message_id', $clientMessageId)
                    ->lockForUpdate()
                    ->first();

                if ($existing) {
                    return $existing;
                }
            }

            $message = ChatMessage::query()->create([
                'municipality_id' => $room->municipality_id,
                'chat_room_id' => $room->id,
                'sender_id' => $sender->id,
                'body' => $body,
                'status' => ChatMessageStatus::Visible,
                'client_message_id' => $clientMessageId,
                'version' => 1,
            ]);

            $this->recorder->record($message, 'sent', $sender, null, ChatMessageStatus::Visible->value);

            $this->sync->dispatch($message, ChatSyncEventType::MessageCreated);

            return $message;
        });
    }
}
