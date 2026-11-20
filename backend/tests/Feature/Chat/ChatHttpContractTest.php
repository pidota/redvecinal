<?php

namespace Tests\Feature\Chat;

use App\Domains\Chat\Enums\ChatMessageStatus;
use App\Domains\Chat\Models\ChatMessage;
use App\Domains\Chat\Models\ChatMessageReport;
use App\Domains\Chat\Services\EnsureGroupChatRoomService;
use App\Domains\Chat\Services\SendChatMessageService;
use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Enums\NeighborhoodGroupStatus;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesChatFixtures;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class ChatHttpContractTest extends TestCase
{
    use CreatesChatFixtures, CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_guest_cannot_list_rooms_or_send(): void
    {
        [$group] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);

        $this->getJson('/api/v1/chat/rooms')->assertUnauthorized();
        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", ['body' => 'Hola'])->assertUnauthorized();
        $this->patchJson('/api/v1/chat/messages/1', ['body' => 'X'])->assertUnauthorized();
        $this->deleteJson('/api/v1/chat/messages/1')->assertUnauthorized();
        $this->postJson('/api/v1/chat/messages/1/report', ['reason_code' => 'spam'])->assertUnauthorized();
    }

    public function test_index_lists_only_rooms_of_active_memberships(): void
    {
        [$groupA, $authorA] = $this->activeGroupTriple();
        [$groupB] = $this->activeGroupTriple();
        $roomA = $this->chatRoomForGroup($groupA);
        $roomB = $this->chatRoomForGroup($groupB);

        Sanctum::actingAs($authorA);
        $response = $this->getJson('/api/v1/chat/rooms')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $roomA->id)
            ->assertJsonPath('data.0.neighborhood_group_id', $groupA->id);

        $ids = collect($response->json('data'))->pluck('id');
        $this->assertFalse($ids->contains($roomB->id));
        $this->assertNoSensitiveFields($response->json());
    }

    public function test_send_rejects_missing_empty_and_too_long_body_with_422(): void
    {
        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);
        Sanctum::actingAs($author);

        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", [])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['body']);

        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", ['body' => '   '])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['body']);

        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", [
            'body' => str_repeat('a', 4001),
        ])->assertStatus(422)->assertJsonValidationErrors(['body']);

        $this->assertDatabaseCount('chat_messages', 0);
    }

    public function test_send_rejects_invalid_client_message_id_and_accepts_uuid(): void
    {
        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);
        Sanctum::actingAs($author);
        $uuid = '550e8400-e29b-41d4-a716-446655440010';

        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", [
            'body' => 'Hola',
            'client_message_id' => 'no-es-uuid',
        ])->assertStatus(422)->assertJsonValidationErrors(['client_message_id']);

        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", [
            'body' => 'Hola',
            'client_message_id' => $uuid,
        ])->assertCreated()->assertJsonPath('data.client_message_id', $uuid);

        $this->assertDatabaseCount('chat_messages', 1);
    }

    public function test_idempotent_replay_keeps_original_payload(): void
    {
        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);
        Sanctum::actingAs($author);
        $uuid = '550e8400-e29b-41d4-a716-446655440011';

        $first = $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", [
            'body' => 'Original',
            'client_message_id' => $uuid,
        ])->assertCreated();

        $second = $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", [
            'body' => 'Distinto',
            'client_message_id' => $uuid,
        ])->assertCreated();

        $this->assertSame($first->json('data.id'), $second->json('data.id'));
        $this->assertSame('Original', $second->json('data.body'));
        $this->assertDatabaseCount('chat_messages', 1);
        $this->assertDatabaseHas('chat_messages', [
            'id' => $first->json('data.id'),
            'body' => 'Original',
            'client_message_id' => $uuid,
        ]);
    }

    public function test_missing_room_returns_404_and_foreign_room_returns_403(): void
    {
        [$groupA, $authorA] = $this->activeGroupTriple();
        [$groupB, $authorB] = $this->activeGroupTriple();
        $roomA = $this->chatRoomForGroup($groupA);
        $this->chatRoomForGroup($groupB);

        Sanctum::actingAs($authorA);
        $this->postJson('/api/v1/chat/rooms/999999/messages', ['body' => 'X'])->assertNotFound();

        Sanctum::actingAs($authorB);
        $this->postJson("/api/v1/chat/rooms/{$roomA->id}/messages", ['body' => 'Intruso'])->assertForbidden();
        $this->assertDatabaseCount('chat_messages', 0);
    }

    public function test_pending_suspended_and_left_members_cannot_mutate_chat(): void
    {
        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);
        $message = app(SendChatMessageService::class)->execute($room, $author, 'Visible');

        foreach ([MembershipStatus::Pending, MembershipStatus::Suspended, MembershipStatus::Left] as $status) {
            $user = $this->memberWithStatus($group, $status);
            Sanctum::actingAs($user);

            $this->getJson('/api/v1/chat/rooms')->assertOk()->assertJsonCount(0, 'data');
            $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", ['body' => 'No'])->assertForbidden();
            $this->patchJson("/api/v1/chat/messages/{$message->id}", ['body' => 'No'])->assertForbidden();
            $this->deleteJson("/api/v1/chat/messages/{$message->id}")->assertForbidden();
            $this->postJson("/api/v1/chat/messages/{$message->id}/report", [
                'reason_code' => 'spam',
            ])->assertForbidden();
        }

        $this->assertDatabaseCount('chat_messages', 1);
        $this->assertDatabaseCount('chat_message_reports', 0);
    }

    public function test_active_president_moderator_and_member_can_send(): void
    {
        [$group, $member, $moderator] = $this->activeGroupTriple();
        $president = User::factory()->create();
        $this->addMemberToGroup($group, $president, MembershipRole::President);
        $room = $this->chatRoomForGroup($group);

        foreach ([$president, $moderator, $member] as $actor) {
            Sanctum::actingAs($actor);
            $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", [
                'body' => 'Desde '.$actor->id,
            ])->assertCreated();
        }

        $this->assertDatabaseCount('chat_messages', 3);
    }

    public function test_municipal_admin_and_superadmin_without_membership_cannot_access_rooms(): void
    {
        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);
        $message = app(SendChatMessageService::class)->execute($room, $author, 'Privado');

        $admin = $this->municipalAdministratorFor($group->municipality);
        Sanctum::actingAs($admin);
        $this->getJson('/api/v1/chat/rooms')->assertOk()->assertJsonCount(0, 'data');
        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", ['body' => 'Admin'])->assertForbidden();
        $this->getJson("/api/v1/chat/messages/{$message->id}")->assertForbidden();

        $super = User::factory()->create();
        $super->assignRole('super-admin');
        Sanctum::actingAs($super);
        $this->getJson('/api/v1/chat/rooms')->assertOk()->assertJsonCount(0, 'data');
        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", ['body' => 'Super'])->assertForbidden();
        $this->patchJson("/api/v1/chat/messages/{$message->id}", ['body' => 'Hack'])->assertForbidden();
    }

    public function test_other_municipality_user_cannot_access_chat(): void
    {
        [$groupA, $authorA] = $this->activeGroupTriple();
        [$groupB, $authorB] = $this->activeGroupTriple();
        $roomA = $this->chatRoomForGroup($groupA);
        $message = app(SendChatMessageService::class)->execute($roomA, $authorA, 'Solo A');

        Sanctum::actingAs($authorB);
        $this->getJson('/api/v1/chat/rooms')
            ->assertOk()
            ->assertJsonMissing(['id' => $roomA->id]);
        $this->getJson("/api/v1/chat/rooms/{$roomA->id}/messages")->assertForbidden();
        $this->postJson("/api/v1/chat/rooms/{$roomA->id}/messages", ['body' => 'B'])->assertForbidden();
        $this->getJson("/api/v1/chat/messages/{$message->id}")->assertForbidden();
        $this->postJson("/api/v1/chat/messages/{$message->id}/report", [
            'reason_code' => 'spam',
        ])->assertForbidden();
    }

    public function test_suspended_group_keeps_read_and_rejects_writes(): void
    {
        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);
        Sanctum::actingAs($author);
        $created = $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", ['body' => 'Antes'])->assertCreated();
        $messageId = $created->json('data.id');

        $group->update(['status' => NeighborhoodGroupStatus::Suspended]);
        app(EnsureGroupChatRoomService::class)->syncRoomStatusForGroup($group->fresh());

        $this->getJson('/api/v1/chat/rooms')->assertOk()->assertJsonCount(1, 'data');
        $this->getJson("/api/v1/chat/rooms/{$room->id}/messages")->assertOk();
        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", ['body' => 'Después'])->assertStatus(422);
        $this->patchJson("/api/v1/chat/messages/{$messageId}", ['body' => 'Edit'])->assertForbidden();
        $this->deleteJson("/api/v1/chat/messages/{$messageId}")->assertForbidden();
    }

    public function test_author_can_patch_and_delete_own_message(): void
    {
        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);
        Sanctum::actingAs($author);
        $id = $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", ['body' => 'Original'])
            ->assertCreated()
            ->json('data.id');

        $this->patchJson("/api/v1/chat/messages/{$id}", ['body' => '   '])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['body']);

        $this->patchJson("/api/v1/chat/messages/{$id}", ['body' => str_repeat('b', 4001)])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['body']);

        $patched = $this->patchJson("/api/v1/chat/messages/{$id}", ['body' => 'Editado'])
            ->assertOk()
            ->assertJsonPath('data.body', 'Editado')
            ->assertJsonPath('data.version', 2);
        $this->assertNoSensitiveFields($patched->json());

        $deleted = $this->deleteJson("/api/v1/chat/messages/{$id}")
            ->assertOk()
            ->assertJsonPath('data.status', ChatMessageStatus::DeletedBySender->value);
        $this->assertNotNull($deleted->json('data.deleted_at'));
        $this->assertDatabaseHas('chat_messages', [
            'id' => $id,
            'status' => ChatMessageStatus::DeletedBySender->value,
        ]);
    }

    public function test_member_cannot_edit_or_delete_foreign_message(): void
    {
        [$group, $author, $other] = $this->twoMembersInGroup();
        $room = $this->chatRoomForGroup($group);
        $message = app(SendChatMessageService::class)->execute($room, $author, 'Ajeno');

        Sanctum::actingAs($other);
        $this->patchJson("/api/v1/chat/messages/{$message->id}", ['body' => 'Hack'])->assertForbidden();
        $this->deleteJson("/api/v1/chat/messages/{$message->id}")->assertForbidden();
        $this->assertDatabaseHas('chat_messages', [
            'id' => $message->id,
            'body' => 'Ajeno',
            'status' => ChatMessageStatus::Visible->value,
        ]);
    }

    public function test_president_can_hide_foreign_message_and_member_cannot(): void
    {
        [$group, $author] = $this->activeGroupTriple();
        $president = User::factory()->create();
        $this->addMemberToGroup($group, $president, MembershipRole::President);
        $room = $this->chatRoomForGroup($group);
        $message = app(SendChatMessageService::class)->execute($room, $author, 'Ocultable');

        Sanctum::actingAs($author);
        $this->postJson("/api/v1/chat/messages/{$message->id}/hide")->assertForbidden();

        Sanctum::actingAs($president);
        $this->postJson("/api/v1/chat/messages/{$message->id}/hide", ['reason' => 'Moderación'])
            ->assertOk()
            ->assertJsonPath('data.status', ChatMessageStatus::Hidden->value);

        Sanctum::actingAs($author);
        $bodies = collect($this->getJson("/api/v1/chat/rooms/{$room->id}/messages")->json('data'))->pluck('body');
        $this->assertFalse($bodies->contains('Ocultable'));
    }

    public function test_hidden_and_deleted_messages_cannot_be_reported_or_edited(): void
    {
        [$group, $author, $reporter] = $this->twoMembersInGroup();
        $room = $this->chatRoomForGroup($group);
        $hidden = app(SendChatMessageService::class)->execute($room, $author, 'Oculto');
        $deleted = app(SendChatMessageService::class)->execute($room, $author, 'Borrado');
        $hidden->update(['status' => ChatMessageStatus::Hidden]);
        $deleted->update(['status' => ChatMessageStatus::DeletedBySender, 'deleted_at' => now()]);

        Sanctum::actingAs($reporter);
        $this->postJson("/api/v1/chat/messages/{$hidden->id}/report", ['reason_code' => 'spam'])->assertForbidden();
        $this->postJson("/api/v1/chat/messages/{$deleted->id}/report", ['reason_code' => 'spam'])->assertForbidden();
        $this->getJson("/api/v1/chat/messages/{$hidden->id}")->assertForbidden();

        Sanctum::actingAs($author);
        $this->patchJson("/api/v1/chat/messages/{$hidden->id}", ['body' => 'No'])->assertForbidden();
        $this->patchJson("/api/v1/chat/messages/{$deleted->id}", ['body' => 'No'])->assertForbidden();
    }

    public function test_report_creates_once_and_duplicate_returns_same_id(): void
    {
        [$group, $author, $reporter] = $this->twoMembersInGroup();
        $room = $this->chatRoomForGroup($group);
        $message = app(SendChatMessageService::class)->execute($room, $author, 'Reportable');

        Sanctum::actingAs($reporter);
        $this->postJson("/api/v1/chat/messages/{$message->id}/report", [])
            ->assertStatus(422)
            ->assertJsonValidationErrors(['reason_code']);

        $first = $this->postJson("/api/v1/chat/messages/{$message->id}/report", [
            'reason_code' => 'spam',
            'details' => 'Texto ofensivo',
        ])->assertCreated();

        $duplicate = $this->postJson("/api/v1/chat/messages/{$message->id}/report", [
            'reason_code' => 'otro',
            'details' => 'Cambio',
        ])->assertCreated();

        $this->assertSame($first->json('id'), $duplicate->json('id'));
        $this->assertDatabaseCount('chat_message_reports', 1);
        $this->assertSame(
            'spam',
            ChatMessageReport::query()->findOrFail($first->json('id'))->reason_code,
        );
        $this->assertNoSensitiveFields($first->json());
        $this->assertArrayNotHasKey('details', $first->json());
        $this->assertArrayNotHasKey('email', $first->json());
    }

    public function test_send_throttle_is_per_user_and_does_not_create_on_429(): void
    {
        config(['red_vecinal.chat.send_per_user_per_minute' => 2]);

        [$group, $author, $other] = $this->twoMembersInGroup();
        $room = $this->chatRoomForGroup($group);

        Sanctum::actingAs($author);
        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", ['body' => 'Uno'])->assertCreated();
        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", ['body' => 'Dos'])->assertCreated();
        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", ['body' => 'Tres'])
            ->assertStatus(429);
        $this->getJson("/api/v1/chat/rooms/{$room->id}/messages")->assertOk();
        $this->getJson('/api/v1/chat/rooms')->assertOk();

        $this->assertSame(2, ChatMessage::query()->where('sender_id', $author->id)->count());

        Sanctum::actingAs($other);
        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", ['body' => 'Otro'])->assertCreated();
        $this->assertDatabaseCount('chat_messages', 3);
    }

    public function test_idempotent_replay_also_consumes_send_throttle(): void
    {
        config(['red_vecinal.chat.send_per_user_per_minute' => 2]);

        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);
        Sanctum::actingAs($author);
        $uuid = '550e8400-e29b-41d4-a716-446655440012';

        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", [
            'body' => 'Uno',
            'client_message_id' => $uuid,
        ])->assertCreated();
        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", ['body' => 'Dos'])->assertCreated();
        $this->postJson("/api/v1/chat/rooms/{$room->id}/messages", [
            'body' => 'Uno',
            'client_message_id' => $uuid,
        ])->assertStatus(429);

        $this->assertDatabaseCount('chat_messages', 2);
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    private function assertNoSensitiveFields(array $payload): void
    {
        $encoded = json_encode($payload, JSON_THROW_ON_ERROR);
        $this->assertStringNotContainsString('"password"', $encoded);
        $this->assertStringNotContainsString('"remember_token"', $encoded);
        $this->assertStringNotContainsString('"email"', $encoded);
    }

    /**
     * @return array{0: NeighborhoodGroup, 1: User, 2: User}
     */
    private function twoMembersInGroup(): array
    {
        [$group, $author] = $this->activeGroupTriple();
        $memberB = User::factory()->create();
        $this->addMemberToGroup($group, $memberB);

        return [$group, $author, $memberB];
    }

    private function memberWithStatus(
        NeighborhoodGroup $group,
        MembershipStatus $status,
    ): User {
        $user = User::factory()->create();
        GroupMember::factory()->create([
            'neighborhood_group_id' => $group->id,
            'municipality_id' => $group->municipality_id,
            'user_id' => $user->id,
            'membership_role' => MembershipRole::Member,
            'status' => $status,
        ]);

        return $user;
    }
}
