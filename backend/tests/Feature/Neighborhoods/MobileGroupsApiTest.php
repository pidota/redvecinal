<?php

namespace Tests\Feature\Neighborhoods;

use App\Domains\Municipality\Models\Municipality;
use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class MobileGroupsApiTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seedPostsBasics();
    }

    public function test_me_groups_includes_municipality_summary(): void
    {
        [$group, $vecino] = $this->vecinoWithGroup();
        Sanctum::actingAs($vecino);

        $this->getJson('/api/v1/me/groups')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $group->id)
            ->assertJsonStructure([
                'data' => [
                    [
                        'id',
                        'municipality_id',
                        'name',
                        'slug',
                        'description',
                        'address',
                        'status',
                        'municipality' => ['id', 'name', 'slug'],
                    ],
                ],
            ])
            ->assertJsonPath('data.0.municipality.id', $group->municipality_id);
    }

    public function test_me_groups_contract_matches_show_and_index(): void
    {
        [$group, $vecino] = $this->vecinoWithGroup();
        Sanctum::actingAs($vecino);

        $me = $this->getJson('/api/v1/me/groups')->assertOk()->json('data.0');

        $show = $this->getJson('/api/v1/groups/'.$group->id)->assertOk()->json('data');

        $this->assertSame($me['municipality'], $show['municipality']);
        $this->assertArrayHasKey('municipality', $show);

        $index = $this->getJson('/api/v1/groups')->assertOk()->json('data');
        $fromIndex = collect($index)->firstWhere('id', $group->id);
        $this->assertNotNull($fromIndex);
        $this->assertSame($me['municipality'], $fromIndex['municipality']);
    }

    public function test_me_groups_lists_only_active_memberships(): void
    {
        $user = User::factory()->create();
        $groupA = NeighborhoodGroup::factory()->create();
        $groupB = NeighborhoodGroup::factory()->create(['municipality_id' => $groupA->municipality_id]);

        GroupMember::factory()->create([
            'neighborhood_group_id' => $groupA->id,
            'municipality_id' => $groupA->municipality_id,
            'user_id' => $user->id,
            'membership_role' => MembershipRole::Member,
            'status' => MembershipStatus::Active,
        ]);
        GroupMember::factory()->create([
            'neighborhood_group_id' => $groupB->id,
            'municipality_id' => $groupB->municipality_id,
            'user_id' => $user->id,
            'membership_role' => MembershipRole::Member,
            'status' => MembershipStatus::Suspended,
        ]);

        Sanctum::actingAs($user);

        $this->getJson('/api/v1/me/groups')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $groupA->id);
    }

    public function test_me_groups_includes_suspended_group_when_membership_active(): void
    {
        $user = User::factory()->create();
        $group = NeighborhoodGroup::factory()->suspended()->create();

        GroupMember::factory()->create([
            'neighborhood_group_id' => $group->id,
            'municipality_id' => $group->municipality_id,
            'user_id' => $user->id,
            'status' => MembershipStatus::Active,
        ]);

        Sanctum::actingAs($user);

        $this->getJson('/api/v1/me/groups')
            ->assertOk()
            ->assertJsonPath('data.0.status', 'suspended');
    }

    public function test_me_groups_is_empty_without_memberships(): void
    {
        Sanctum::actingAs(User::factory()->create());

        $this->getJson('/api/v1/me/groups')->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_groups_index_respects_municipal_isolation(): void
    {
        $municipalityA = Municipality::factory()->create();
        $municipalityB = Municipality::factory()->create();

        $groupA = NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityA->id]);
        NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityB->id]);

        $user = User::factory()->create();
        GroupMember::factory()->create([
            'neighborhood_group_id' => $groupA->id,
            'municipality_id' => $municipalityA->id,
            'user_id' => $user->id,
            'status' => MembershipStatus::Active,
        ]);

        Sanctum::actingAs($user);

        $ids = collect($this->getJson('/api/v1/groups')->assertOk()->json('data'))->pluck('id');

        $this->assertTrue($ids->contains($groupA->id));
        $this->assertSame(1, $ids->count());
    }

    public function test_show_hides_sensitive_contact_fields_and_includes_municipality(): void
    {
        $user = User::factory()->create();
        $user->assignRole('super-admin');
        $group = NeighborhoodGroup::factory()->create([
            'contact_email' => 'privado@example.com',
            'contact_phone' => '+56912345678',
        ]);
        Sanctum::actingAs($user);

        $this->getJson('/api/v1/groups/'.$group->id)
            ->assertOk()
            ->assertJsonStructure(['data' => ['municipality' => ['id', 'name', 'slug']]])
            ->assertJsonMissing(['contact_email', 'contact_phone']);
    }

    public function test_me_groups_requires_authentication(): void
    {
        $this->getJson('/api/v1/me/groups')->assertUnauthorized();
    }

    public function test_suspended_membership_cannot_view_group(): void
    {
        $password = 'secret';
        $user = User::factory()->create(['password' => Hash::make($password)]);
        $group = NeighborhoodGroup::factory()->create();
        $member = GroupMember::factory()->create([
            'neighborhood_group_id' => $group->id,
            'municipality_id' => $group->municipality_id,
            'user_id' => $user->id,
            'status' => MembershipStatus::Suspended,
        ]);

        Sanctum::actingAs($user);

        $this->getJson('/api/v1/groups/'.$group->id)->assertForbidden();
        $this->getJson('/api/v1/me/groups')->assertOk()->assertJsonCount(0, 'data');
        $member->update(['status' => MembershipStatus::Active]);
        $this->app['auth']->forgetGuards();
        Sanctum::actingAs($user->fresh());
        $this->getJson('/api/v1/me/groups')->assertJsonCount(1, 'data');
    }

    /**
     * @return array{0: NeighborhoodGroup, 1: User}
     */
    private function vecinoWithGroup(): array
    {
        $group = NeighborhoodGroup::factory()->create();
        $vecino = User::factory()->create();
        $this->addMemberToGroup($group, $vecino);

        return [$group, $vecino];
    }
}
