<?php

namespace Tests\Feature\Chat;

use App\Domains\Chat\Enums\ChatSyncEventType;
use App\Domains\Chat\Events\ChatRoomSyncBroadcast;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Event;
use Tests\Concerns\CreatesChatFixtures;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class ChatBroadcastTest extends TestCase
{
    use CreatesChatFixtures, CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
        Event::fake([ChatRoomSyncBroadcast::class]);
    }

    public function test_send_message_dispatches_sync_event_after_commit_without_body(): void
    {
        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);

        app(\App\Domains\Chat\Services\SendChatMessageService::class)->execute($room, $author, 'Secreto');

        Event::assertDispatched(ChatRoomSyncBroadcast::class, function (ChatRoomSyncBroadcast $event) use ($room) {
            $payload = $event->broadcastWith();

            return $event->eventType === ChatSyncEventType::MessageCreated
                && $payload['room_id'] === $room->id
                && isset($payload['message_id'])
                && isset($payload['version'])
                && ! array_key_exists('body', $payload);
        });
    }
}
