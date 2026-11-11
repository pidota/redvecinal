<?php

namespace Tests\Feature\Chat;

use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Enums\NeighborhoodGroupStatus;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Broadcast;
use Tests\Concerns\CreatesChatFixtures;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class ChatBroadcastingAuthTest extends TestCase
{
    use CreatesChatFixtures, CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
        $this->configurePusherBroadcasterForChannelAuth();
    }

    public function test_active_member_can_authorize_broadcasting_auth(): void
    {
        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group)->load('neighborhoodGroup');

        $this->assertTrue(app(\App\Domains\Chat\Support\ChatMembershipGuard::class)->canReadRoom($author, $room));

        $this->actingAs($author, 'sanctum');

        $this->postJson('/broadcasting/auth', [
            'channel_name' => "private-chat.room.{$room->id}",
            'socket_id' => '1234.5678',
        ])->assertOk()
            ->assertJsonStructure(['auth']);
    }

    public function test_foreign_member_is_denied_broadcasting_auth(): void
    {
        [$groupA] = $this->activeGroupTriple();
        [, $intruder] = $this->activeGroupTriple();
        $roomA = $this->chatRoomForGroup($groupA);

        $this->actingAs($intruder, 'sanctum');

        $this->postJson('/broadcasting/auth', [
            'channel_name' => "private-chat.room.{$roomA->id}",
            'socket_id' => '2.2',
        ])->assertForbidden();
    }

    public function test_suspended_member_is_denied_broadcasting_auth(): void
    {
        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);
        $author->groupMemberships()->update(['status' => MembershipStatus::Suspended]);

        $this->actingAs($author->fresh(), 'sanctum');

        $this->postJson('/broadcasting/auth', [
            'channel_name' => "private-chat.room.{$room->id}",
            'socket_id' => '3.3',
        ])->assertForbidden();
    }

    public function test_suspended_group_member_with_active_membership_can_still_authorize_read_channel(): void
    {
        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);
        $group->update(['status' => NeighborhoodGroupStatus::Suspended]);
        app(\App\Domains\Chat\Services\EnsureGroupChatRoomService::class)->syncRoomStatusForGroup($group->fresh());

        $this->actingAs($author, 'sanctum');

        $this->postJson('/broadcasting/auth', [
            'channel_name' => "private-chat.room.{$room->id}",
            'socket_id' => '1234.5679',
        ])->assertOk();
    }

    public function test_unauthenticated_broadcasting_auth_is_denied(): void
    {
        [$group] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);

        $this->postJson('/broadcasting/auth', [
            'channel_name' => "private-chat.room.{$room->id}",
            'socket_id' => '5.5',
        ])->assertUnauthorized();
    }

    private function configurePusherBroadcasterForChannelAuth(): void
    {
        config([
            'broadcasting.default' => 'pusher',
            'broadcasting.connections.pusher' => [
                'driver' => 'pusher',
                'key' => 'phpunit-pusher-key',
                'secret' => 'phpunit-pusher-secret',
                'app_id' => '12345',
                'options' => [
                    'cluster' => 'mt1',
                    'host' => '127.0.0.1',
                    'port' => 6001,
                    'scheme' => 'http',
                    'encrypted' => false,
                    'useTLS' => false,
                ],
                'client_options' => [],
            ],
        ]);

        Broadcast::purge('pusher');

        require base_path('routes/channels.php');
    }
}
