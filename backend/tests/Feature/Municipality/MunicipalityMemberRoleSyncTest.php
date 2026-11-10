<?php

namespace Tests\Feature\Municipality;

use App\Domains\Municipality\Enums\MunicipalityMemberRole;
use App\Domains\Municipality\Enums\MunicipalityMemberStatus;
use App\Domains\Municipality\Models\Municipality;
use App\Domains\Municipality\Models\MunicipalityMember;
use App\Domains\Municipality\Services\MunicipalityMemberRoleSynchronizer;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class MunicipalityMemberRoleSyncTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);
    }

    public function test_active_administrator_membership_assigns_spatie_role(): void
    {
        $user = User::factory()->create();

        MunicipalityMember::factory()->create([
            'user_id' => $user->id,
            'role' => MunicipalityMemberRole::Administrador,
            'status' => MunicipalityMemberStatus::Active,
        ]);

        $this->assertTrue($user->fresh()->hasRole('administrador-municipal'));
    }

    public function test_inactive_administrator_membership_revokes_spatie_role(): void
    {
        $user = User::factory()->create();

        $member = MunicipalityMember::factory()->create([
            'user_id' => $user->id,
            'role' => MunicipalityMemberRole::Administrador,
            'status' => MunicipalityMemberStatus::Active,
        ]);

        $member->update(['status' => MunicipalityMemberStatus::Inactive]);

        $this->assertFalse($user->fresh()->hasRole('administrador-municipal'));
    }

    public function test_keeps_role_while_administrator_in_another_municipality(): void
    {
        $user = User::factory()->create();
        $municipalityA = Municipality::factory()->create();
        $municipalityB = Municipality::factory()->create();

        $memberA = MunicipalityMember::factory()->create([
            'municipality_id' => $municipalityA->id,
            'user_id' => $user->id,
            'role' => MunicipalityMemberRole::Administrador,
            'status' => MunicipalityMemberStatus::Active,
        ]);

        MunicipalityMember::factory()->create([
            'municipality_id' => $municipalityB->id,
            'user_id' => $user->id,
            'role' => MunicipalityMemberRole::Administrador,
            'status' => MunicipalityMemberStatus::Active,
        ]);

        $memberA->delete();

        $this->assertTrue($user->fresh()->hasRole('administrador-municipal'));
    }

    public function test_super_admin_role_is_never_removed_by_synchronizer(): void
    {
        $user = User::factory()->create();
        $user->assignRole('super-admin');

        MunicipalityMember::factory()->create([
            'user_id' => $user->id,
            'role' => MunicipalityMemberRole::Administrador,
            'status' => MunicipalityMemberStatus::Inactive,
        ]);

        app(MunicipalityMemberRoleSynchronizer::class)->sync($user->fresh());

        $this->assertTrue($user->fresh()->hasRole('super-admin'));
        $this->assertTrue($user->fresh()->canAccessPanel(filament()->getPanel('admin')));
    }

    public function test_funcionario_membership_does_not_assign_panel_role(): void
    {
        $user = User::factory()->create();

        MunicipalityMember::factory()->create([
            'user_id' => $user->id,
            'role' => MunicipalityMemberRole::Funcionario,
            'status' => MunicipalityMemberStatus::Active,
        ]);

        $this->assertFalse($user->fresh()->hasRole('administrador-municipal'));
    }

    public function test_municipal_admin_cannot_assign_administrator_role_via_policy(): void
    {
        $municipalAdmin = User::factory()->create();
        $municipalAdmin->assignRole('administrador-municipal');

        $this->assertFalse($municipalAdmin->can('assignAdministradorRole', MunicipalityMember::class));
    }

    public function test_municipal_admin_cannot_update_own_membership(): void
    {
        $municipalAdmin = User::factory()->create();
        $member = MunicipalityMember::factory()->create([
            'user_id' => $municipalAdmin->id,
            'role' => MunicipalityMemberRole::Administrador,
            'status' => MunicipalityMemberStatus::Active,
        ]);

        $this->assertFalse($municipalAdmin->can('update', $member));
    }
}
