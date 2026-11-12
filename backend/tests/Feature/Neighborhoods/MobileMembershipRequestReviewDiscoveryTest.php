<?php

namespace Tests\Feature\Neighborhoods;

use App\Domains\Neighborhoods\Enums\MembershipRequestStatus;
use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Models\NeighborhoodMembershipRequest;
use App\Domains\Neighborhoods\Policies\NeighborhoodMembershipRequestPolicy;
use App\Domains\Neighborhoods\Services\AddGroupMemberService;
use App\Domains\Neighborhoods\Services\AssignPresidentService;
use App\Domains\Neighborhoods\Support\ReviewableNeighborhoodGroupsQuery;
use App\Domains\Municipality\Models\Municipality;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class MobileMembershipRequestReviewDiscoveryTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seedPostsBasics();
    }

    public function test_president_discovers_only_authorized_groups(): void
    {
        $municipality = Municipality::factory()->create();
        $groupA = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id, 'name' => 'Junta A']);
        $groupB = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id, 'name' => 'Junta B']);
        $presidentA = $this->makePresidentFor($groupA);

        Sanctum::actingAs($presidentA);

        $response = $this->getJson('/api/v1/me/reviewable-groups')->assertOk();
        $ids = collect($response->json('data'))->pluck('id');

        $this->assertTrue($ids->contains($groupA->id));
        $this->assertFalse($ids->contains($groupB->id));
    }

    public function test_suspended_president_discovers_no_groups(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $president = $this->makePresidentFor($group);

        GroupMember::query()
            ->where('neighborhood_group_id', $group->id)
            ->where('user_id', $president->id)
            ->update(['status' => MembershipStatus::Suspended]);

        Sanctum::actingAs($president);

        $this->getJson('/api/v1/me/reviewable-groups')
            ->assertOk()
            ->assertJsonPath('data', []);
    }

    public function test_municipal_admin_discovers_groups_without_membership(): void
    {
        $municipality = Municipality::factory()->create();
        $group = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id]);
        $admin = $this->municipalAdministratorFor($municipality);

        Sanctum::actingAs($admin);

        $this->getJson('/api/v1/me/reviewable-groups')
            ->assertOk()
            ->assertJsonPath('data.0.id', $group->id);
    }

    public function test_municipal_admin_does_not_discover_foreign_municipality(): void
    {
        $municipalityA = Municipality::factory()->create();
        $municipalityB = Municipality::factory()->create();
        NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityB->id]);
        $adminA = $this->municipalAdministratorFor($municipalityA);

        Sanctum::actingAs($adminA);

        $this->getJson('/api/v1/me/reviewable-groups')
            ->assertOk()
            ->assertJsonPath('data', []);
    }

    public function test_superadmin_discovers_administrable_groups_across_municipalities(): void
    {
        $municipalityA = Municipality::factory()->create();
        $municipalityB = Municipality::factory()->create();
        $groupA = NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityA->id]);
        $groupB = NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityB->id]);

        $super = User::factory()->create();
        $super->assignRole('super-admin');
        Sanctum::actingAs($super);

        $ids = collect($this->getJson('/api/v1/me/reviewable-groups')->json('data'))->pluck('id');
        $this->assertTrue($ids->contains($groupA->id));
        $this->assertTrue($ids->contains($groupB->id));
    }

    public function test_moderator_discovers_no_reviewable_groups_when_only_moderator(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $moderator = User::factory()->create();
        $this->addMemberToGroup($group, $moderator, MembershipRole::Moderator);

        Sanctum::actingAs($moderator);

        $this->getJson('/api/v1/me/reviewable-groups')
            ->assertOk()
            ->assertJsonPath('data', []);
    }

    public function test_common_neighbor_discovers_no_groups(): void
    {
        [$group, $vecino] = $this->vecinoWithGroup();
        $other = NeighborhoodGroup::factory()->create(['municipality_id' => $group->municipality_id]);
        $this->addMemberToGroup($other, $vecino);

        Sanctum::actingAs($vecino);

        $this->getJson('/api/v1/me/reviewable-groups')
            ->assertOk()
            ->assertJsonPath('data', []);
    }

    public function test_suspended_group_not_in_reviewable_list(): void
    {
        $municipality = Municipality::factory()->create();
        $suspended = NeighborhoodGroup::factory()->suspended()->create(['municipality_id' => $municipality->id]);
        $admin = $this->municipalAdministratorFor($municipality);

        Sanctum::actingAs($admin);

        $ids = collect($this->getJson('/api/v1/me/reviewable-groups')->json('data'))->pluck('id');
        $this->assertFalse($ids->contains($suspended->id));
    }

    public function test_reviewable_groups_require_authentication(): void
    {
        $this->getJson('/api/v1/me/reviewable-groups')->assertUnauthorized();
    }

    public function test_reviewable_groups_pagination_is_stable_without_duplicates(): void
    {
        $municipality = Municipality::factory()->create();
        NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id, 'name' => 'Alpha']);
        NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id, 'name' => 'Beta']);
        NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id, 'name' => 'Gamma']);
        $admin = $this->municipalAdministratorFor($municipality);

        Sanctum::actingAs($admin);

        $page1 = $this->getJson('/api/v1/me/reviewable-groups?page=1')->assertOk();
        $names = collect($page1->json('data'))->pluck('name')->values()->all();

        $this->assertSame(['Alpha', 'Beta', 'Gamma'], $names);
        $this->assertCount(3, collect($page1->json('data'))->pluck('id')->unique());
    }

    public function test_group_requests_filter_pending(): void
    {
        [$anchor, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create(['municipality_id' => $anchor->municipality_id]);
        $president = $this->makePresidentFor($target);

        Sanctum::actingAs($vecino);
        $pendingId = $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->json('data.id');

        NeighborhoodMembershipRequest::factory()
            ->forGroupAndUser($target, User::factory()->create())
            ->create(['status' => MembershipRequestStatus::Rejected]);

        Sanctum::actingAs($president);
        $response = $this->getJson("/api/v1/groups/{$target->id}/membership-requests?status=pending")
            ->assertOk();

        $ids = collect($response->json('data'))->pluck('id');
        $this->assertTrue($ids->contains($pendingId));
        $this->assertCount(1, $ids);
    }

    public function test_group_requests_filters_all_statuses(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $president = $this->makePresidentFor($group);

        foreach (MembershipRequestStatus::cases() as $status) {
            NeighborhoodMembershipRequest::factory()
                ->forGroupAndUser($group, User::factory()->create())
                ->create(['status' => $status]);
        }

        Sanctum::actingAs($president);

        foreach (MembershipRequestStatus::cases() as $status) {
            $count = $this->getJson("/api/v1/groups/{$group->id}/membership-requests?status={$status->value}")
                ->assertOk()
                ->json('meta.total');
            $this->assertSame(1, $count, "Filtro {$status->value}");
        }
    }

    public function test_group_requests_invalid_status_returns_422(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $president = $this->makePresidentFor($group);

        Sanctum::actingAs($president);

        $this->getJson("/api/v1/groups/{$group->id}/membership-requests?status=invalid")
            ->assertStatus(422);
    }

    public function test_group_requests_without_filter_keeps_previous_contract(): void
    {
        [$anchor, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create(['municipality_id' => $anchor->municipality_id]);
        $president = $this->makePresidentFor($target);

        Sanctum::actingAs($vecino);
        $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->assertCreated();

        NeighborhoodMembershipRequest::factory()
            ->forGroupAndUser($target, User::factory()->create())
            ->create(['status' => MembershipRequestStatus::Approved]);

        Sanctum::actingAs($president);
        $this->getJson("/api/v1/groups/{$target->id}/membership-requests")
            ->assertOk()
            ->assertJsonStructure(['data', 'links', 'meta'])
            ->assertJsonCount(2, 'data');
    }

    public function test_unauthorized_user_cannot_list_foreign_group_requests(): void
    {
        $municipality = Municipality::factory()->create();
        $groupA = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id]);
        $groupB = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id]);
        $presidentA = $this->makePresidentFor($groupA);

        Sanctum::actingAs($presidentA);

        $this->getJson("/api/v1/groups/{$groupB->id}/membership-requests")->assertForbidden();
    }

    public function test_reviewable_query_matches_policy_for_each_group(): void
    {
        $municipality = Municipality::factory()->create();
        $group = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id]);
        $president = $this->makePresidentFor($group);
        $admin = $this->municipalAdministratorFor($municipality);

        $policy = app(NeighborhoodMembershipRequestPolicy::class);

        foreach ([$president, $admin] as $user) {
            $groups = ReviewableNeighborhoodGroupsQuery::forUser($user)->get();
            foreach ($groups as $listed) {
                $this->assertTrue(
                    $policy->canReviewMembershipRequests($user, $listed),
                    "Usuario {$user->id} junta {$listed->id} en consulta pero policy niega",
                );
            }
        }
    }

    public function test_moderator_municipal_admin_excludes_moderated_group_from_reviewable(): void
    {
        $municipality = Municipality::factory()->create();
        $moderated = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id, 'name' => 'Con moderador']);
        $other = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id, 'name' => 'Otra junta']);
        $admin = $this->municipalAdministratorFor($municipality);
        $this->addMemberToGroup($moderated, $admin, MembershipRole::Moderator);

        Sanctum::actingAs($admin);

        $ids = collect($this->getJson('/api/v1/me/reviewable-groups')->json('data'))->pluck('id');
        $this->assertFalse($ids->contains($moderated->id));
        $this->assertTrue($ids->contains($other->id));
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

    private function makePresidentFor(NeighborhoodGroup $group): User
    {
        $president = User::factory()->create();
        $admin = User::factory()->create();
        $add = app(AddGroupMemberService::class);
        $add->execute($group, $president, $admin, MembershipStatus::Active);
        app(AssignPresidentService::class)->execute($group, $president, $admin);

        return $president;
    }
}
