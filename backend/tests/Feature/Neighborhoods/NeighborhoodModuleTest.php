<?php

namespace Tests\Feature\Neighborhoods;

use App\Domains\Municipality\Enums\MunicipalityMemberRole;
use App\Domains\Municipality\Enums\MunicipalityMemberStatus;
use App\Domains\Municipality\Models\Municipality;
use App\Domains\Municipality\Models\MunicipalityMember;
use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Enums\NeighborhoodGroupStatus;
use App\Domains\Neighborhoods\Exceptions\NeighborhoodDomainException;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Services\AddGroupMemberService;
use App\Domains\Neighborhoods\Services\AssignPresidentService;
use App\Domains\Neighborhoods\Services\CreateNeighborhoodGroupService;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Validation\ValidationException;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class NeighborhoodModuleTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);
    }

  public function test_can_create_neighborhood_group(): void
    {
        $municipality = Municipality::factory()->create();
        $service = app(CreateNeighborhoodGroupService::class);

        $group = $service->execute($municipality, ['name' => 'Junta Centro']);

        $this->assertDatabaseHas('neighborhood_groups', [
            'id' => $group->id,
            'slug' => 'junta-centro',
        ]);
    }

    public function test_slug_must_be_unique_per_municipality(): void
    {
        $municipality = Municipality::factory()->create();
        $service = app(CreateNeighborhoodGroupService::class);
        $service->execute($municipality, ['name' => 'Junta Norte', 'slug' => 'junta-norte']);

        $this->expectException(ValidationException::class);
        $service->execute($municipality, ['name' => 'Otra', 'slug' => 'junta-norte']);
    }

    public function test_prevents_duplicate_membership(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $user = User::factory()->create();
        $actor = User::factory()->create();
        $service = app(AddGroupMemberService::class);
        $service->execute($group, $user, $actor);

        $this->expectException(NeighborhoodDomainException::class);
        $service->execute($group, $user, $actor);
    }

    public function test_only_one_active_president_per_group(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $presidentA = User::factory()->create();
        $presidentB = User::factory()->create();
        $admin = User::factory()->create();

        $add = app(AddGroupMemberService::class);
        $add->execute($group, $presidentA, $admin, MembershipStatus::Active);
        $add->execute($group, $presidentB, $admin, MembershipStatus::Active);

        $assign = app(AssignPresidentService::class);
        $assign->execute($group, $presidentA, $admin);

        $this->expectException(QueryException::class);
        GroupMember::query()->create([
            'municipality_id' => $group->municipality_id,
            'neighborhood_group_id' => $group->id,
            'user_id' => User::factory()->create()->id,
            'membership_role' => MembershipRole::President,
            'status' => MembershipStatus::Active,
            'joined_at' => now(),
        ]);
    }

    public function test_user_can_be_president_of_multiple_groups(): void
    {
        $user = User::factory()->create();
        $admin = User::factory()->create();
        $groupA = NeighborhoodGroup::factory()->create();
        $groupB = NeighborhoodGroup::factory()->create(['municipality_id' => $groupA->municipality_id]);

        $add = app(AddGroupMemberService::class);
        $assign = app(AssignPresidentService::class);

        foreach ([$groupA, $groupB] as $group) {
            $add->execute($group, $user, $admin, MembershipStatus::Active);
            $assign->execute($group, $user, $admin);
        }

        $this->assertSame(2, GroupMember::query()
            ->where('user_id', $user->id)
            ->where('membership_role', MembershipRole::President)
            ->where('status', MembershipStatus::Active)
            ->count());
    }

    public function test_municipality_integrity_enforced_at_database_level(): void
    {
        $municipalityA = Municipality::factory()->create();
        $municipalityB = Municipality::factory()->create();
        $group = NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityA->id]);

        $this->expectException(QueryException::class);

        GroupMember::query()->create([
            'municipality_id' => $municipalityB->id,
            'neighborhood_group_id' => $group->id,
            'user_id' => User::factory()->create()->id,
            'membership_role' => MembershipRole::Member,
            'status' => MembershipStatus::Active,
        ]);
    }

    public function test_suspended_group_blocks_member_addition(): void
    {
        $group = NeighborhoodGroup::factory()->suspended()->create();
        $service = app(AddGroupMemberService::class);

        $this->expectException(NeighborhoodDomainException::class);
        $service->execute($group, User::factory()->create(), User::factory()->create());
    }

    public function test_president_cannot_assign_president(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $president = User::factory()->create();
        $member = User::factory()->create();
        $admin = User::factory()->create();

        $add = app(AddGroupMemberService::class);
        $add->execute($group, $president, $admin, MembershipStatus::Active);
        $add->execute($group, $member, $admin, MembershipStatus::Active);
        app(AssignPresidentService::class)->execute($group, $president, $admin);

        $presidentMember = GroupMember::query()->where('user_id', $president->id)->first();
        $target = GroupMember::query()->where('user_id', $member->id)->first();

        $this->assertFalse($president->can('assignPresident', $target));
    }

    public function test_moderator_cannot_approve_members(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $moderator = User::factory()->create();
        $pending = User::factory()->create();
        $admin = User::factory()->create();

        $add = app(AddGroupMemberService::class);
        $add->execute($group, $moderator, $admin, MembershipStatus::Active, MembershipRole::Moderator);
        $pendingMember = $add->execute($group, $pending, $admin);

        $this->assertFalse($moderator->can('approve', $pendingMember));
    }

    public function test_municipal_administrator_cannot_access_other_municipality_group(): void
    {
        $municipalityA = Municipality::factory()->create();
        $municipalityB = Municipality::factory()->create();
        $groupB = NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityB->id]);

        $admin = User::factory()->create();
        $admin->assignRole('administrador-municipal');
        MunicipalityMember::factory()->create([
            'municipality_id' => $municipalityA->id,
            'user_id' => $admin->id,
            'role' => MunicipalityMemberRole::Administrador,
            'status' => MunicipalityMemberStatus::Active,
        ]);

        $this->assertFalse($admin->can('view', $groupB));
    }

    public function test_super_admin_retains_panel_access(): void
    {
        $user = User::factory()->create();
        $user->assignRole('super-admin');

        $this->assertTrue($user->canAccessPanel(filament()->getPanel('admin')));
    }

    public function test_roles_and_permissions_seeder_is_idempotent(): void
    {
        $this->seed(RolesAndPermissionsSeeder::class);
        $permissions = \Spatie\Permission\Models\Permission::count();

        $this->seed(RolesAndPermissionsSeeder::class);

        $this->assertSame($permissions, \Spatie\Permission\Models\Permission::count());
    }

    public function test_api_requires_authentication(): void
    {
        $this->getJson('/api/v1/groups')->assertUnauthorized();
    }

    public function test_api_hides_sensitive_contact_fields(): void
    {
        $user = User::factory()->create();
        $user->assignRole('super-admin');
        Sanctum::actingAs($user);

        $group = NeighborhoodGroup::factory()->create([
            'contact_email' => 'privado@example.com',
            'contact_phone' => '+56912345678',
        ]);

        $this->getJson('/api/v1/groups/'.$group->id)
            ->assertOk()
            ->assertJsonMissing(['contact_email', 'contact_phone']);
    }

    public function test_president_can_only_administer_own_group(): void
    {
        $municipality = Municipality::factory()->create();
        $groupA = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id]);
        $groupB = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id]);

        $president = User::factory()->create();
        $admin = User::factory()->create();

        $add = app(AddGroupMemberService::class);
        $add->execute($groupA, $president, $admin, MembershipStatus::Active);
        app(AssignPresidentService::class)->execute($groupA, $president, $admin);

        $foreignMember = $add->execute($groupB, User::factory()->create(), $admin);

        $this->assertTrue($president->can('create', [GroupMember::class, $groupA]));
        $this->assertFalse($president->can('create', [GroupMember::class, $groupB]));
        $this->assertFalse($president->can('approve', $foreignMember));
    }

    public function test_assign_president_service_replaces_existing_president(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $oldPresident = User::factory()->create();
        $newPresident = User::factory()->create();
        $admin = User::factory()->create();

        $add = app(AddGroupMemberService::class);
        $add->execute($group, $oldPresident, $admin, MembershipStatus::Active);
        $add->execute($group, $newPresident, $admin, MembershipStatus::Active);

        $assign = app(AssignPresidentService::class);
        $assign->execute($group, $oldPresident, $admin);
        $assign->execute($group, $newPresident, $admin);

        $this->assertDatabaseHas('group_members', [
            'user_id' => $oldPresident->id,
            'membership_role' => MembershipRole::Member->value,
        ]);

        $this->assertDatabaseHas('group_members', [
            'user_id' => $newPresident->id,
            'membership_role' => MembershipRole::President->value,
        ]);
    }

    public function test_inactive_group_status_blocks_administration(): void
    {
        $group = NeighborhoodGroup::factory()->create(['status' => NeighborhoodGroupStatus::Inactive]);

        $this->assertFalse($group->isAdministrable());
    }
}
