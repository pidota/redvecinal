<?php

namespace Tests\Feature\Chat;

use App\Domains\Chat\Models\ChatRoom;
use App\Domains\Chat\Support\ChatMembershipGuard;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\CreatesChatFixtures;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class ChatChannelAuthorizationTest extends TestCase
{
    use CreatesChatFixtures, CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_member_can_authorize_private_chat_channel(): void
    {
        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group)->load('neighborhoodGroup');

        $this->assertTrue($this->channelAllowsUser($author, $room));
    }

    public function test_non_member_cannot_authorize_private_chat_channel(): void
    {
        [$groupA] = $this->activeGroupTriple();
        [, $intruder] = $this->activeGroupTriple();
        $roomA = $this->chatRoomForGroup($groupA)->load('neighborhoodGroup');

        $this->assertFalse($this->channelAllowsUser($intruder, $roomA));
    }

    public function test_suspended_member_cannot_authorize_channel(): void
    {
        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group)->load('neighborhoodGroup');
        $author->groupMemberships()->update(['status' => MembershipStatus::Suspended]);

        $this->assertFalse($this->channelAllowsUser($author->fresh(), $room));
    }

    /**
     * Misma lógica que routes/channels.php (el driver null no implementa Broadcast::auth).
     */
    private function channelAllowsUser(\App\Models\User $user, ChatRoom $room): bool
    {
        return app(ChatMembershipGuard::class)->canReadRoom($user, $room);
    }
}
