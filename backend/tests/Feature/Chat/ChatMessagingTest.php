<?php

namespace Tests\Feature\Chat;

use App\Domains\Chat\Enums\ChatMessageStatus;
use App\Domains\Neighborhoods\Enums\NeighborhoodGroupStatus;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesChatFixtures;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class ChatMessagingTest extends TestCase
{
    use CreatesChatFixtures, CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_active_member_can_send_and_list_messages(): void
    {
        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);
        Sanctum::actingAs($author);

        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", [
            'body' => 'Hola vecinos',
            'client_message_id' => '550e8400-e29b-41d4-a716-446655440000',
        ])->assertCreated();

        $this->getJson("/api/v1/chat/rooms/{$room->id}/messages")
            ->assertOk()
            ->assertJsonPath('data.0.body', 'Hola vecinos');
    }

    public function test_foreign_group_member_cannot_access_room_messages(): void
    {
        [$groupA, $authorA] = $this->activeGroupTriple();
        [$groupB, $authorB] = $this->activeGroupTriple();
        $roomA = $this->chatRoomForGroup($groupA);
        Sanctum::actingAs($authorB);

        $this->getJson("/api/v1/chat/rooms/{$roomA->id}/messages")->assertForbidden();
    }

    public function test_client_message_id_is_idempotent(): void
    {
        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);
        Sanctum::actingAs($author);
        $uuid = '550e8400-e29b-41d4-a716-446655440001';

        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", ['body' => 'Uno', 'client_message_id' => $uuid])->assertCreated();
        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", ['body' => 'Uno', 'client_message_id' => $uuid])->assertCreated();

        $this->assertDatabaseCount('chat_messages', 1);
    }

    public function test_suspended_group_allows_read_but_blocks_send(): void
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);
        Sanctum::actingAs($author);
        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", ['body' => 'Antes'])->assertCreated();

        $group->update(['status' => NeighborhoodGroupStatus::Suspended]);
        app(\App\Domains\Chat\Services\EnsureGroupChatRoomService::class)->syncRoomStatusForGroup($group->fresh());

        $this->getJson("/api/v1/chat/rooms/{$room->id}/messages")->assertOk();
        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", ['body' => 'Bloqueado'])->assertStatus(422);
    }

    public function test_unread_count_excludes_own_messages(): void
    {
        [$group, $authorA, $authorB] = $this->twoMembersInGroup();
        $room = $this->chatRoomForGroup($group);

        Sanctum::actingAs($authorA);
        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", ['body' => 'M1']);
        Sanctum::actingAs($authorB);
        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", ['body' => 'M2']);

        Sanctum::actingAs($authorA);
        $this->getJson("/api/v1/chat/rooms/{$room->id}/unread-count")
            ->assertOk()
            ->assertJsonPath('unread_count', 1);
    }

    public function test_moderator_can_hide_foreign_message(): void
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);
        Sanctum::actingAs($author);
        $response = $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", ['body' => 'Inapropiado']);
        $messageId = $response->json('data.id');

        Sanctum::actingAs($moderator);
        $this->postJson("/api/v1/chat/messages/{$messageId}/hide", ['reason' => 'Spam'])->assertOk();

        Sanctum::actingAs($author);
        $bodies = collect($this->getJson("/api/v1/chat/rooms/{$room->id}/messages")->json('data'))->pluck('body');
        $this->assertNotContains('Inapropiado', $bodies);
    }

    private function twoMembersInGroup(): array
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $memberB = \App\Models\User::factory()->create();
        $this->addMemberToGroup($group, $memberB);

        return [$group, $author, $memberB];
    }
}
