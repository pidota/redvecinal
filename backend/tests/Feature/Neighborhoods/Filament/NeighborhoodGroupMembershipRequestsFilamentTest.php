<?php

namespace Tests\Feature\Neighborhoods\Filament;

use App\Domains\Municipality\Models\Municipality;
use App\Domains\Neighborhoods\Enums\MembershipRequestStatus;
use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Models\NeighborhoodMembershipRequest;
use App\Domains\Neighborhoods\Policies\NeighborhoodMembershipRequestPolicy;
use App\Domains\Neighborhoods\Services\AddGroupMemberService;
use App\Domains\Neighborhoods\Services\ApproveMembershipRequestService;
use App\Domains\Neighborhoods\Services\AssignPresidentService;
use App\Filament\Resources\NeighborhoodGroups\Pages\EditNeighborhoodGroup;
use App\Filament\Resources\NeighborhoodGroups\RelationManagers\MembershipIncorporationRequestsRelationManager;
use App\Filament\Resources\NeighborhoodGroups\RelationManagers\MembershipsRelationManager;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Filament\Facades\Filament;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Tests\Concerns\CreatesPostFixtures;
use Tests\Concerns\InteractsWithFilamentPanel;
use Tests\TestCase;

class NeighborhoodGroupMembershipRequestsFilamentTest extends TestCase
{
    use CreatesPostFixtures, InteractsWithFilamentPanel, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seedPostsBasics();
    }

    public function test_authorized_municipal_admin_sees_mobile_requests_for_own_municipality(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $applicant = User::factory()->create();
        $request = NeighborhoodMembershipRequest::factory()
            ->forGroupAndUser($group, $applicant)
            ->create(['request_note' => 'Hola']);

        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(MembershipIncorporationRequestsRelationManager::class, [
            'ownerRecord' => $group,
            'pageClass' => EditNeighborhoodGroup::class,
        ])
            ->assertSuccessful()
            ->assertCanSeeTableRecords([$request])
            ->assertSee('Solicitudes de incorporación (app móvil)')
            ->assertSee($applicant->name);
    }

    public function test_direct_livewire_mount_returns_forbidden_without_review_permission(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        NeighborhoodMembershipRequest::factory()
            ->forGroupAndUser($group, User::factory()->create())
            ->create();

        $intruder = User::factory()->create();
        $intruder->assignRole('administrador-municipal');
        $this->authenticateForFilament($intruder);

        Livewire::test(MembershipIncorporationRequestsRelationManager::class, [
            'ownerRecord' => $group,
            'pageClass' => EditNeighborhoodGroup::class,
        ])->assertForbidden();
    }

    public function test_table_lists_only_requests_for_owner_group(): void
    {
        $municipality = Municipality::factory()->create();
        $groupA = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id]);
        $groupB = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id]);

        $requestA = NeighborhoodMembershipRequest::factory()
            ->forGroupAndUser($groupA, User::factory()->create())
            ->create();
        $requestB = NeighborhoodMembershipRequest::factory()
            ->forGroupAndUser($groupB, User::factory()->create())
            ->create();

        $admin = $this->municipalAdministratorFor($municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(MembershipIncorporationRequestsRelationManager::class, [
            'ownerRecord' => $groupA,
            'pageClass' => EditNeighborhoodGroup::class,
        ])
            ->assertSuccessful()
            ->assertCanSeeTableRecords([$requestA])
            ->assertCanNotSeeTableRecords([$requestB]);
    }

    public function test_pending_badge_hidden_without_review_permission(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        NeighborhoodMembershipRequest::factory()
            ->forGroupAndUser($group, User::factory()->create())
            ->create();

        $intruder = User::factory()->create();
        Filament::auth()->login($intruder);

        $this->assertNull(
            MembershipIncorporationRequestsRelationManager::getBadge($group, EditNeighborhoodGroup::class)
        );

        $admin = $this->municipalAdministratorFor($group->municipality);
        Filament::auth()->login($admin);

        $this->assertSame(
            '1',
            MembershipIncorporationRequestsRelationManager::getBadge($group, EditNeighborhoodGroup::class)
        );
    }

    public function test_foreign_municipality_admin_cannot_view_group_requests(): void
    {
        $municipalityA = Municipality::factory()->create();
        $municipalityB = Municipality::factory()->create();
        $groupA = NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityA->id]);
        $groupB = NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityB->id]);

        $applicant = User::factory()->create();
        NeighborhoodMembershipRequest::factory()->forGroupAndUser($groupB, $applicant)->create();

        $adminA = $this->municipalAdministratorFor($municipalityA);
        $this->authenticateForFilament($adminA);

        $this->assertFalse($adminA->can('view', $groupB));

        Livewire::test(MembershipIncorporationRequestsRelationManager::class, [
            'ownerRecord' => $groupB,
            'pageClass' => EditNeighborhoodGroup::class,
        ])->assertForbidden();
    }

    public function test_president_can_review_via_policy_but_not_filament_panel(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $president = User::factory()->create();
        $admin = User::factory()->create();
        app(AddGroupMemberService::class)->execute($group, $president, $admin, MembershipStatus::Active);
        app(AssignPresidentService::class)->execute($group, $president, $admin);

        $policy = app(NeighborhoodMembershipRequestPolicy::class);
        $this->assertTrue($policy->canReviewMembershipRequests($president->fresh(), $group->fresh()));
        $this->assertFalse($president->canAccessPanel(Filament::getPanel('admin')));
    }

    public function test_municipal_role_without_membership_cannot_view_any_requests(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $operator = User::factory()->create();
        $operator->assignRole('administrador-municipal');

        $policy = app(NeighborhoodMembershipRequestPolicy::class);
        $this->assertFalse($policy->viewAny($operator, $group));

        Filament::auth()->login($operator);
        $this->assertFalse(
            MembershipIncorporationRequestsRelationManager::canViewForRecord($group, EditNeighborhoodGroup::class)
        );
    }

    public function test_active_moderator_without_review_permission_cannot_view_requests_tab(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $moderator = User::factory()->create();
        GroupMember::factory()->create([
            'neighborhood_group_id' => $group->id,
            'municipality_id' => $group->municipality_id,
            'user_id' => $moderator->id,
            'membership_role' => MembershipRole::Moderator,
            'status' => MembershipStatus::Active,
        ]);
        $moderator->assignRole('administrador-municipal');
        $moderator->revokePermissionTo('group-members.approve');

        $this->authenticateForFilament($moderator);

        Livewire::test(MembershipIncorporationRequestsRelationManager::class, [
            'ownerRecord' => $group,
            'pageClass' => EditNeighborhoodGroup::class,
        ])->assertForbidden();
    }

    public function test_api_pending_request_not_listed_as_panel_pending_member(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $applicant = User::factory()->create();
        NeighborhoodMembershipRequest::factory()->forGroupAndUser($group, $applicant)->create();

        $this->assertFalse(
            GroupMember::query()
                ->where('neighborhood_group_id', $group->id)
                ->where('user_id', $applicant->id)
                ->where('status', MembershipStatus::Pending)
                ->exists()
        );

        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(MembershipsRelationManager::class, [
            'ownerRecord' => $group,
            'pageClass' => EditNeighborhoodGroup::class,
        ])->assertSuccessful()
            ->assertCanNotSeeTableRecords(
                GroupMember::query()
                    ->where('neighborhood_group_id', $group->id)
                    ->where('user_id', $applicant->id)
                    ->get()
            );
    }

    public function test_approved_api_request_appears_as_active_member_in_integrantes(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $vecino = User::factory()->create();
        $president = User::factory()->create();
        $admin = User::factory()->create();
        app(AddGroupMemberService::class)->execute($group, $president, $admin, MembershipStatus::Active);
        app(AssignPresidentService::class)->execute($group, $president, $admin);

        $membershipRequest = NeighborhoodMembershipRequest::factory()->forGroupAndUser($group, $vecino)->create();

        app(ApproveMembershipRequestService::class)->execute($membershipRequest, $president, null);

        $activeMember = GroupMember::query()
            ->where('neighborhood_group_id', $group->id)
            ->where('user_id', $vecino->id)
            ->where('status', MembershipStatus::Active)
            ->first();

        $this->assertNotNull($activeMember);

        $this->authenticateForFilament($this->municipalAdministratorFor($group->municipality));

        Livewire::test(MembershipsRelationManager::class, [
            'ownerRecord' => $group->fresh(),
            'pageClass' => EditNeighborhoodGroup::class,
        ])->assertSuccessful()
            ->assertCanSeeTableRecords([$activeMember]);
    }

    public function test_requests_table_has_no_mutation_actions(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        $component = Livewire::test(MembershipIncorporationRequestsRelationManager::class, [
            'ownerRecord' => $group,
            'pageClass' => EditNeighborhoodGroup::class,
        ])->assertSuccessful();

        $this->assertSame([], $component->instance()->getTable()->getHeaderActions());
        $this->assertSame([], $component->instance()->getTable()->getActions());
        $this->assertSame([], $component->instance()->getTable()->getBulkActions());
    }

    public function test_empty_state_when_no_pending_requests_with_default_filter(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $applicant = User::factory()->create();
        NeighborhoodMembershipRequest::factory()
            ->forGroupAndUser($group, $applicant)
            ->create(['status' => MembershipRequestStatus::Approved, 'reviewed_at' => now()]);

        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(MembershipIncorporationRequestsRelationManager::class, [
            'ownerRecord' => $group,
            'pageClass' => EditNeighborhoodGroup::class,
        ])
            ->assertSuccessful()
            ->assertSee('Sin solicitudes para mostrar');
    }
}