<?php

namespace App\Domains\Chat\Events;

use App\Domains\Chat\Enums\ChatSyncEventType;
use App\Domains\Chat\Models\ChatMessage;
use Illuminate\Broadcasting\Channel;
use Illuminate\Broadcasting\InteractsWithSockets;
use Illuminate\Broadcasting\PrivateChannel;
use Illuminate\Contracts\Broadcasting\ShouldBroadcast;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class ChatRoomSyncBroadcast implements ShouldBroadcast
{
    use Dispatchable, InteractsWithSockets, SerializesModels;

    /**
     * Único mecanismo de emisión post-commit (no usar {@see DB::afterCommit} adicional).
     *
     * @var bool
     */
    public $afterCommit = true;

    public function __construct(
        public readonly ChatMessage $message,
        public readonly ChatSyncEventType $eventType,
    ) {}

    public function broadcastOn(): Channel
    {
        return new PrivateChannel('chat.room.'.$this->message->chat_room_id);
    }

    public function broadcastAs(): string
    {
        return 'chat.sync';
    }

    /**
     * @return array<string, int|string>
     */
    public function broadcastWith(): array
    {
        return [
            'room_id' => $this->message->chat_room_id,
            'message_id' => $this->message->id,
            'event_type' => $this->eventType->value,
            'version' => $this->message->version,
        ];
    }
}
