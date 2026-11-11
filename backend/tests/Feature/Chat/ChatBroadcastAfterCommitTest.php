<?php

namespace Tests\Feature\Chat;

use App\Domains\Chat\Enums\ChatMessageStatus;
use App\Domains\Chat\Enums\ChatSyncEventType;
use App\Domains\Chat\Events\ChatRoomSyncBroadcast;
use App\Domains\Chat\Models\ChatMessage;
use App\Domains\Chat\Services\SendChatMessageService;
use Illuminate\Broadcasting\BroadcastEvent;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Event;
use Illuminate\Support\Facades\Queue;
use Tests\Concerns\CreatesChatFixtures;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class ChatBroadcastAfterCommitTest extends TestCase
{
    use CreatesChatFixtures, CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_rolled_back_transaction_does_not_persist_message(): void
    {
        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);

        try {
            DB::transaction(function () use ($room, $author) {
                ChatMessage::query()->create([
                    'municipality_id' => $room->municipality_id,
                    'chat_room_id' => $room->id,
                    'sender_id' => $author->id,
                    'body' => 'rollback',
                    'status' => ChatMessageStatus::Visible,
                    'version' => 1,
                ]);

                event(new ChatRoomSyncBroadcast(
                    ChatMessage::query()->latest('id')->first(),
                    ChatSyncEventType::MessageCreated,
                ));

                throw new \RuntimeException('forced rollback');
            });
        } catch (\RuntimeException) {
            //
        }

        $this->assertDatabaseCount('chat_messages', 0);
    }

    public function test_send_message_queues_single_broadcast_after_commit(): void
    {
        Queue::fake();

        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);

        app(SendChatMessageService::class)->execute($room, $author, 'Hola');

        Queue::assertPushed(BroadcastEvent::class, 1);
    }

    public function test_idempotent_resend_does_not_queue_extra_broadcast(): void
    {
        Queue::fake();

        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);
        $uuid = '550e8400-e29b-41d4-a716-446655440099';
        $send = app(SendChatMessageService::class);

        $send->execute($room, $author, 'Uno', $uuid);
        $send->execute($room, $author, 'Uno', $uuid);

        Queue::assertPushed(BroadcastEvent::class, 1);
    }

    public function test_sync_event_is_emitted_inside_transaction_relying_on_after_commit_flag(): void
    {
        Event::fake([ChatRoomSyncBroadcast::class]);

        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);

        app(SendChatMessageService::class)->execute($room, $author, 'Dentro de TX');

        Event::assertDispatched(ChatRoomSyncBroadcast::class, function (ChatRoomSyncBroadcast $event) {
            return $event->afterCommit === true
                && $event->broadcastWith()['event_type'] === ChatSyncEventType::MessageCreated->value
                && ! array_key_exists('body', $event->broadcastWith());
        });
    }
}
