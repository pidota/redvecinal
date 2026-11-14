<?php

namespace Tests\Feature\Neighborhoods\Filament;

use App\Domains\Neighborhoods\Enums\MembershipRequestStatus;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Models\NeighborhoodMembershipRequest;
use App\Domains\Neighborhoods\Services\AddGroupMemberService;
use App\Domains\Neighborhoods\Services\AssignPresidentService;
use App\Filament\Resources\NeighborhoodGroups\Pages\EditNeighborhoodGroup;
use App\Filament\Resources\NeighborhoodGroups\RelationManagers\MembershipIncorporationRequestsRelationManager;
use App\Filament\Resources\NeighborhoodGroups\RelationManagers\MembershipsRelationManager;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Spatie\Permission\Models\Role;
use Tests\Concerns\CreatesPostFixtures;
use Tests\Concerns\InteractsWithFilamentPanel;
use Tests\TestCase;

class NeighborhoodGroupFilamentClarityTest extends TestCase
{
    use CreatesPostFixtures, InteractsWithFilamentPanel, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seedPostsBasics();
    }

    public function test_integrantes_tab_exposes_existing_header_actions(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        $component = Livewire::test(MembershipsRelationManager::class, [
            'ownerRecord' => $group,
            'pageClass' => EditNeighborhoodGroup::class,
        ])->assertSuccessful()
            ->assertSee('Integrantes de la junta (panel municipal)');

        $headerNames = collect($component->instance()->getTable()->getHeaderActions())
            ->map(fn ($action) => $action->getName())
            ->all();

        $this->assertContains('addExisting', $headerNames);
        $this->assertContains('createUser', $headerNames);
    }

    public function test_mobile_requests_tab_remains_read_only(): void
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
    }

    public function test_panel_pending_member_not_shown_as_mobile_request(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $vecino = User::factory()->create();
        $admin = User::factory()->create();
        $member = app(AddGroupMemberService::class)->execute($group, $vecino, $admin);

        $this->assertSame(MembershipStatus::Pending, $member->status);
        $this->assertFalse(
            NeighborhoodMembershipRequest::query()
                ->where('neighborhood_group_id', $group->id)
                ->where('user_id', $vecino->id)
                ->exists()
        );

        $this->authenticateForFilament($this->municipalAdministratorFor($group->municipality));

        Livewire::test(MembershipIncorporationRequestsRelationManager::class, [
            'ownerRecord' => $group,
            'pageClass' => EditNeighborhoodGroup::class,
        ])->assertSuccessful()
            ->assertSee('Sin solicitudes móviles con este filtro');
    }

    public function test_mobile_pending_not_shown_as_panel_pending_member(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $applicant = User::factory()->create();
        NeighborhoodMembershipRequest::factory()->forGroupAndUser($group, $applicant)->create();

        $this->authenticateForFilament($this->municipalAdministratorFor($group->municipality));

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

    public function test_manual_add_blocked_when_mobile_request_pending(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $applicant = User::factory()->create();
        NeighborhoodMembershipRequest::factory()->forGroupAndUser($group, $applicant)->create();
        $admin = User::factory()->create();

        $this->expectException(\App\Domains\Neighborhoods\Exceptions\NeighborhoodDomainException::class);
        $this->expectExceptionMessage('app móvil');

        app(AddGroupMemberService::class)->execute($group, $applicant, $admin);
    }

    public function test_manual_add_conflict_copy_points_to_mobile_requests_tab(): void
    {
        $domainMessage = 'El usuario tiene una solicitud de incorporación pendiente en la app móvil.';
        $adminCopy = 'Este vecino tiene una solicitud de incorporación pendiente en la app móvil para esta junta. '
            .'Revise la pestaña «Solicitudes de incorporación». La decisión debe tomarse desde la aplicación móvil o esperando a que el vecino cancele la solicitud.';

        $this->assertStringContainsString('app móvil', $domainMessage);
        $this->assertStringContainsString('Solicitudes de incorporación', $adminCopy);
        $this->assertStringNotContainsString('municipalidad', strtolower($adminCopy));
    }

    public function test_resolved_mobile_request_status_labels_visible_in_filter(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $user = User::factory()->create(['email' => 'resuelto@example.test']);

        NeighborhoodMembershipRequest::factory()->forGroupAndUser($group, $user)->create([
            'status' => MembershipRequestStatus::Rejected,
            'rejected_at' => now(),
        ]);

        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(MembershipIncorporationRequestsRelationManager::class, [
            'ownerRecord' => $group,
            'pageClass' => EditNeighborhoodGroup::class,
        ])
            ->filterTable('status', MembershipRequestStatus::Rejected->value)
            ->assertSuccessful()
            ->assertSee('Rechazada (app móvil)');
    }

    public function test_empty_mobile_requests_state_clarifies_integrantes_may_exist(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $vecino = User::factory()->create();
        GroupMember::factory()->create([
            'neighborhood_group_id' => $group->id,
            'municipality_id' => $group->municipality_id,
            'user_id' => $vecino->id,
            'status' => MembershipStatus::Active,
        ]);

        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(MembershipIncorporationRequestsRelationManager::class, [
            'ownerRecord' => $group,
            'pageClass' => EditNeighborhoodGroup::class,
        ])
            ->assertSuccessful()
            ->assertSee('Esto no significa que la junta no tenga integrantes');
    }

    public function test_requester_email_hidden_without_group_members_view(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $applicant = User::factory()->create([
            'name' => 'Vecino Prueba',
            'email' => 'correo-oculto-e32@example.test',
        ]);
        NeighborhoodMembershipRequest::factory()->forGroupAndUser($group, $applicant)->create();

        $reviewer = $this->filamentReviewerWithoutMemberEmailView($group);

        $this->authenticateForFilament($reviewer);
        $this->assertFalse($reviewer->can('group-members.view'));

        Livewire::test(MembershipIncorporationRequestsRelationManager::class, [
            'ownerRecord' => $group,
            'pageClass' => EditNeighborhoodGroup::class,
        ])
            ->assertSuccessful()
            ->assertSee('Vecino Prueba')
            ->assertDontSee('correo-oculto-e32@example.test');
    }

    public function test_municipal_isolation_still_applies_after_copy_changes(): void
    {
        $municipalityA = \App\Domains\Municipality\Models\Municipality::factory()->create();
        $groupB = NeighborhoodGroup::factory()->create([
            'municipality_id' => \App\Domains\Municipality\Models\Municipality::factory()->create()->id,
        ]);
        $adminA = $this->municipalAdministratorFor($municipalityA);
        $this->authenticateForFilament($adminA);

        Livewire::test(MembershipIncorporationRequestsRelationManager::class, [
            'ownerRecord' => $groupB,
            'pageClass' => EditNeighborhoodGroup::class,
        ])->assertForbidden();
    }

    private function filamentReviewerWithoutMemberEmailView(NeighborhoodGroup $group): User
    {
        $president = User::factory()->create();
        $bootstrap = User::factory()->create();
        app(AddGroupMemberService::class)->execute($group, $president, $bootstrap, MembershipStatus::Active);
        app(AssignPresidentService::class)->execute($group, $president, $bootstrap);

        $roleName = 'junta-revisor-sin-correo-e32';
        config([
            'red_vecinal.filament_panel_roles' => array_values(array_unique(array_merge(
                config('red_vecinal.filament_panel_roles', []),
                [$roleName],
            ))),
        ]);

        $role = Role::firstOrCreate(['name' => $roleName, 'guard_name' => 'web']);
        $role->syncPermissions([
            'neighborhood-groups.view',
            'group-members.approve',
        ]);
        $president->assignRole($roleName);

        return $president->fresh();
    }
}