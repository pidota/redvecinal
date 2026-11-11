<?php

namespace App\Domains\Chat\Services;

use App\Domains\Chat\Enums\ChatMessageStatus;
use App\Domains\Chat\Exceptions\ChatDomainException;
use App\Domains\Chat\Models\ChatMessage;
use App\Domains\Chat\Models\ChatReadState;
use App\Domains\Chat\Models\ChatRoom;
use App\Domains\Chat\Support\ChatMembershipGuard;
use App\Models\User;
use Illuminate\Support\Facades\DB;

class MarkChatRoomReadService
{
    public function __construct(private readonly ChatMembershipGuard $guard) {}

    public function execute(ChatRoom $room, User $user, ?int $lastReadMessageId = null): ChatReadState
    {
        $this->guard->assertCanReadRoom($user, $room);

        return DB::transaction(function () use ($room, $user, $lastReadMessageId) {
            $state = ChatReadState::query()->firstOrCreate(
                [
                    'chat_room_id' => $room->id,
                    'user_id' => $user->id,
                ],
                [
                    'municipality_id' => $room->municipality_id,
                ],
            );

            $targetId = $lastReadMessageId ?? $this->latestVisibleMessageId($room);
            if ($targetId === null) {
                $state->update(['last_read_at' => now()]);

                return $state->fresh();
            }

            $message = ChatMessage::query()
                ->whereKey($targetId)
                ->where('chat_room_id', $room->id)
                ->where('municipality_id', $room->municipality_id)
                ->first();

            if (! $message) {
                throw new ChatDomainException('Mensaje de lectura inválido para esta sala.');
            }

            if ($state->last_read_message_id !== null && $targetId < $state->last_read_message_id) {
                throw new ChatDomainException('No se puede retroceder el marcador de lectura.');
            }

            $state->update([
                'last_read_message_id' => $targetId,
                'last_read_at' => now(),
            ]);

            return $state->fresh();
        });
    }

    private function latestVisibleMessageId(ChatRoom $room): ?int
    {
        return ChatMessage::query()
            ->where('chat_room_id', $room->id)
            ->where('status', ChatMessageStatus::Visible)
            ->max('id');
    }
}
