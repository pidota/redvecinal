<?php

namespace Tests\Feature\Chat;

use App\Domains\Chat\Enums\ChatMessageStatus;
use App\Domains\Chat\Models\ChatMessage;
use App\Domains\Chat\Models\ChatRoom;
use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesChatFixtures;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class ChatMessagePaginationTest extends TestCase
{
    use CreatesChatFixtures, CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_without_cursor_returns_latest_thirty_in_asc_order(): void
    {
        [$room, $author, $ids] = $this->roomWithVisibleMessages(120);
        Sanctum::actingAs($author);

        $response = $this->getJson("/api/v1/chat/rooms/{$room->id}/messages")
            ->assertOk();
        $returned = collect($response->json('data'))->pluck('id')->all();

        $this->assertCount(30, $returned);
        $this->assertSame(array_slice($ids, -30), $returned);
        $this->assertSame($returned, collect($returned)->sort()->values()->all());
        $this->assertSame($ids[90], $returned[0]);
        $this->assertSame($ids[119], $returned[29]);
    }

    public function test_before_id_returns_immediately_previous_page(): void
    {
        [$room, $author, $ids] = $this->roomWithVisibleMessages(120);
        Sanctum::actingAs($author);

        $latest = $this->getJson("/api/v1/chat/rooms/{$room->id}/messages")->json('data');
        $minLatest = $latest[0]['id'];

        $previous = collect($this->getJson(
            "/api/v1/chat/rooms/{$room->id}/messages?before_id={$minLatest}",
        )->json('data'))->pluck('id')->all();

        $this->assertSame(array_slice($ids, 60, 30), $previous);
        $this->assertSame($previous, collect($previous)->sort()->values()->all());
        $this->assertEmpty(array_intersect($previous, collect($latest)->pluck('id')->all()));
    }

    public function test_after_id_returns_following_page(): void
    {
        [$room, $author, $ids] = $this->roomWithVisibleMessages(120);
        Sanctum::actingAs($author);

        $after = collect($this->getJson(
            "/api/v1/chat/rooms/{$room->id}/messages?after_id={$ids[89]}",
        )->json('data'))->pluck('id')->all();

        $this->assertSame(array_slice($ids, 90, 30), $after);
        $this->assertSame($after, collect($after)->sort()->values()->all());
    }

    public function test_before_id_at_start_and_after_id_at_end_are_empty(): void
    {
        [$room, $author, $ids] = $this->roomWithVisibleMessages(120);
        Sanctum::actingAs($author);

        $this->getJson("/api/v1/chat/rooms/{$room->id}/messages?before_id={$ids[0]}")
            ->assertOk()
            ->assertJsonCount(0, 'data');
        $this->getJson("/api/v1/chat/rooms/{$room->id}/messages?after_id={$ids[119]}")
            ->assertOk()
            ->assertJsonCount(0, 'data');
    }

    public function test_limit_bounds_and_both_cursors_rejected(): void
    {
        [$room, $author, $ids] = $this->roomWithVisibleMessages(120);
        Sanctum::actingAs($author);

        $one = collect($this->getJson("/api/v1/chat/rooms/{$room->id}/messages?limit=1")->json('data'))
            ->pluck('id')
            ->all();
        $this->assertSame([$ids[119]], $one);

        $hundred = collect($this->getJson("/api/v1/chat/rooms/{$room->id}/messages?limit=100")->json('data'))
            ->pluck('id')
            ->all();
        $this->assertCount(100, $hundred);
        $this->assertSame(array_slice($ids, 20), $hundred);

        $this->getJson("/api/v1/chat/rooms/{$room->id}/messages?limit=101")
            ->assertStatus(422)
            ->assertJsonValidationErrors(['limit']);

        $this->getJson("/api/v1/chat/rooms/{$room->id}/messages?after_id={$ids[10]}&before_id={$ids[50]}")
            ->assertStatus(422);
    }

    public function test_cursors_follow_visible_ids_when_not_consecutive(): void
    {
        [$room, $author, $ids] = $this->roomWithVisibleMessages(100);
        $hidden = [$ids[40], $ids[41], $ids[85]];
        ChatMessage::query()->whereKey($hidden)->update(['status' => ChatMessageStatus::Hidden]);
        Sanctum::actingAs($author);

        $visible = array_values(array_filter(
            $ids,
            fn (int $id): bool => ! in_array($id, $hidden, true),
        ));

        $latest = collect($this->getJson("/api/v1/chat/rooms/{$room->id}/messages")->json('data'))
            ->pluck('id')
            ->all();
        $this->assertSame(array_slice($visible, -30), $latest);

        $previous = collect($this->getJson(
            "/api/v1/chat/rooms/{$room->id}/messages?before_id={$latest[0]}",
        )->json('data'))->pluck('id')->all();
        $this->assertSame(array_slice($visible, -60, 30), $previous);
        $this->assertEmpty(array_intersect($previous, $latest));

        $after = collect($this->getJson(
            "/api/v1/chat/rooms/{$room->id}/messages?after_id={$previous[29]}",
        )->json('data'))->pluck('id')->all();
        $this->assertSame($latest, $after);
    }

    public function test_pages_do_not_omit_or_duplicate_visible_messages(): void
    {
        [$room, $author, $ids] = $this->roomWithVisibleMessages(100);
        Sanctum::actingAs($author);

        $page1 = collect($this->getJson("/api/v1/chat/rooms/{$room->id}/messages")->json('data'))->pluck('id');
        $page2 = collect($this->getJson(
            "/api/v1/chat/rooms/{$room->id}/messages?before_id={$page1->first()}",
        )->json('data'))->pluck('id');
        $page3 = collect($this->getJson(
            "/api/v1/chat/rooms/{$room->id}/messages?before_id={$page2->first()}",
        )->json('data'))->pluck('id');
        $page4 = collect($this->getJson(
            "/api/v1/chat/rooms/{$room->id}/messages?before_id={$page3->first()}",
        )->json('data'))->pluck('id');

        $merged = $page1->concat($page2)->concat($page3)->concat($page4);
        $this->assertSame($merged->unique()->count(), $merged->count());
        $this->assertSame($ids, $merged->sort()->values()->all());
    }

    public function test_hidden_and_deleted_respect_visibility_with_id_gaps(): void
    {
        [$room, $author, $ids] = $this->roomWithVisibleMessages(110);
        $moderator = GroupMember::query()
            ->where('neighborhood_group_id', $room->neighborhood_group_id)
            ->where('membership_role', MembershipRole::Moderator)
            ->firstOrFail()
            ->user;

        ChatMessage::query()->whereKey($ids[94])->update(['status' => ChatMessageStatus::Hidden]);
        ChatMessage::query()->whereKey($ids[95])->update([
            'status' => ChatMessageStatus::DeletedBySender,
            'deleted_at' => now(),
        ]);

        Sanctum::actingAs($author);
        $memberIds = collect($this->getJson("/api/v1/chat/rooms/{$room->id}/messages?limit=40")->json('data'))
            ->pluck('id');
        $this->assertFalse($memberIds->contains($ids[94]));
        $this->assertTrue($memberIds->contains($ids[95]));
        $this->assertTrue($memberIds->contains($ids[109]));
        $this->assertSame($memberIds->all(), $memberIds->sort()->values()->all());

        Sanctum::actingAs($moderator);
        $modIds = collect($this->getJson("/api/v1/chat/rooms/{$room->id}/messages?limit=40")->json('data'))
            ->pluck('id');
        $this->assertTrue($modIds->contains($ids[94]));
        $this->assertFalse($modIds->contains($ids[95]));
    }

    public function test_foreign_and_revoked_members_cannot_list(): void
    {
        [$room, $author] = $this->roomWithVisibleMessages(100);
        [$otherGroup, $other] = $this->activeGroupTriple();
        $this->chatRoomForGroup($otherGroup);

        Sanctum::actingAs($other);
        $this->getJson("/api/v1/chat/rooms/{$room->id}/messages")->assertForbidden();

        $revoked = User::factory()->create();
        GroupMember::factory()->create([
            'neighborhood_group_id' => $room->neighborhood_group_id,
            'municipality_id' => $room->municipality_id,
            'user_id' => $revoked->id,
            'status' => MembershipStatus::Suspended,
        ]);
        Sanctum::actingAs($revoked);
        $this->getJson("/api/v1/chat/rooms/{$room->id}/messages")->assertForbidden();
        $this->assertNotNull($author);
    }

    public function test_municipal_isolation(): void
    {
        [$roomA, $authorA] = $this->roomWithVisibleMessages(100);
        [$roomB, $authorB] = $this->roomWithVisibleMessages(100);

        Sanctum::actingAs($authorB);
        $this->getJson("/api/v1/chat/rooms/{$roomA->id}/messages")->assertForbidden();
        $this->getJson("/api/v1/chat/rooms/{$roomB->id}/messages")
            ->assertOk()
            ->assertJsonCount(30, 'data');
        $this->assertNotSame($roomA->municipality_id, $roomB->municipality_id);
        $this->assertNotNull($authorA);
    }

    /**
     * @return array{0: ChatRoom, 1: User, 2: list<int>}
     */
    private function roomWithVisibleMessages(int $count): array
    {
        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);
        $ids = [];
        for ($i = 1; $i <= $count; $i++) {
            $ids[] = ChatMessage::query()->create([
                'municipality_id' => $room->municipality_id,
                'chat_room_id' => $room->id,
                'sender_id' => $author->id,
                'body' => 'msg-'.$i,
                'status' => ChatMessageStatus::Visible,
                'version' => 1,
            ])->id;
        }

        return [$room, $author, $ids];
    }
}
