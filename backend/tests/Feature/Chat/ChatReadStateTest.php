<?php

namespace Tests\Feature\Chat;

use App\Domains\Chat\Exceptions\ChatDomainException;
use App\Domains\Chat\Services\MarkChatRoomReadService;
use App\Domains\Chat\Services\SendChatMessageService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesChatFixtures;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class ChatReadStateTest extends TestCase
{
    use CreatesChatFixtures, CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_cannot_regress_read_marker(): void
    {
        [$group, $reader, $other] = $this->twoMembersInGroup();
        $room = $this->chatRoomForGroup($group);
        $send = app(SendChatMessageService::class);
        $m1 = $send->execute($room, $other, 'A');
        $m2 = $send->execute($room, $other, 'B');
        $mark = app(MarkChatRoomReadService::class);

        $mark->execute($room, $reader, $m2->id);

        $this->expectException(ChatDomainException::class);
        $mark->execute($room, $reader, $m1->id);
    }

    public function test_mark_read_rejects_message_from_other_room(): void
    {
        [$groupA, , $userA] = $this->twoMembersInGroup();
        [$groupB, , $userB] = $this->twoMembersInGroup();
        $roomA = $this->chatRoomForGroup($groupA);
        $roomB = $this->chatRoomForGroup($groupB);
        $foreignMessage = app(SendChatMessageService::class)->execute($roomB, $userB, 'X');

        $this->expectException(ChatDomainException::class);
        app(MarkChatRoomReadService::class)->execute($roomA, $userA, $foreignMessage->id);
    }

    public function test_empty_room_can_mark_read_without_message_id(): void
    {
        [$group, $reader] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);

        $state = app(MarkChatRoomReadService::class)->execute($room, $reader, null);

        $this->assertNull($state->last_read_message_id);
        $this->assertNotNull($state->last_read_at);
    }

    public function test_api_read_updates_unread_count(): void
    {
        [$group, $reader, $other] = $this->twoMembersInGroup();
        $room = $this->chatRoomForGroup($group);
        app(SendChatMessageService::class)->execute($room, $other, 'Nuevo');

        Sanctum::actingAs($reader);
        $this->getJson("/api/v1/chat/rooms/{$room->id}/unread-count")
            ->assertJsonPath('unread_count', 1);

        $messageId = (int) $room->messages()->max('id');
        $this->postJson("/api/v1/chat/rooms/{$room->id}/read", ['last_read_message_id' => $messageId])
            ->assertOk();

        $this->getJson("/api/v1/chat/rooms/{$room->id}/unread-count")
            ->assertJsonPath('unread_count', 0);
    }

    private function twoMembersInGroup(): array
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $memberB = \App\Models\User::factory()->create();
        $this->addMemberToGroup($group, $memberB);

        return [$group, $author, $memberB];
    }
}
