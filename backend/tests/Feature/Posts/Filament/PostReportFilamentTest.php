<?php

namespace Tests\Feature\Posts\Filament;

use App\Domains\Municipality\Enums\MunicipalityMemberRole;
use App\Domains\Municipality\Enums\MunicipalityMemberStatus;
use App\Domains\Municipality\Models\MunicipalityMember;
use App\Domains\Posts\Enums\PostReportStatus;
use App\Domains\Posts\Models\PostReport;
use App\Filament\Resources\PostReports\Pages\ListPostReports;
use App\Filament\Resources\PostReports\Pages\ViewPostReport;
use App\Filament\Resources\PostReports\PostReportResource;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Spatie\Permission\Models\Role;
use Spatie\Permission\PermissionRegistrar;
use Tests\Concerns\CreatesPostFixtures;
use Tests\Concerns\InteractsWithFilamentPanel;
use Tests\TestCase;

class PostReportFilamentTest extends TestCase
{
    use CreatesPostFixtures, InteractsWithFilamentPanel, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
        Role::findOrCreate('super-admin', 'web');
        Role::findOrCreate('administrador-municipal', 'web');
    }

    public function test_municipal_admin_sees_only_own_municipality_reports(): void
    {
        [$groupA, $authorA, , $postA] = $this->publishedCommunityPost();
        [$groupB, $authorB, , $postB] = $this->publishedCommunityPost();

        $reportA = $this->createReport($postA, $authorA);
        $reportB = $this->createReport($postB, $authorB);

        $adminA = $this->municipalAdministratorFor($groupA->municipality);
        $this->authenticateForFilament($adminA);

        $visibleIds = PostReportResource::getEloquentQuery()->pluck('id')->all();
        $this->assertContains($reportA->id, $visibleIds);
        $this->assertNotContains($reportB->id, $visibleIds);

        Livewire::test(ListPostReports::class)
            ->assertCanSeeTableRecords([$reportA])
            ->assertCanNotSeeTableRecords([$reportB]);
    }

    public function test_admin_with_non_admin_membership_in_other_municipality_does_not_see_those_reports(): void
    {
        [$groupA, $authorA, , $postA] = $this->publishedCommunityPost();
        [$groupB, $authorB, , $postB] = $this->publishedCommunityPost();
        $reportA = $this->createReport($postA, $authorA);
        $reportB = $this->createReport($postB, $authorB);

        $adminA = $this->municipalAdministratorFor($groupA->municipality);
        MunicipalityMember::factory()->create([
            'municipality_id' => $groupB->municipality_id,
            'user_id' => $adminA->id,
            'role' => MunicipalityMemberRole::Funcionario,
            'status' => MunicipalityMemberStatus::Active,
        ]);

        $this->authenticateForFilament($adminA->fresh());

        $visibleIds = PostReportResource::getEloquentQuery()->pluck('id')->all();
        $this->assertContains($reportA->id, $visibleIds);
        $this->assertNotContains($reportB->id, $visibleIds);

        Livewire::test(ListPostReports::class)
            ->assertCanSeeTableRecords([$reportA])
            ->assertCanNotSeeTableRecords([$reportB]);
    }

    public function test_super_admin_with_permission_sees_reports_from_both_municipalities(): void
    {
        [$groupA, $authorA, , $postA] = $this->publishedCommunityPost();
        [$groupB, $authorB, , $postB] = $this->publishedCommunityPost();
        $reportA = $this->createReport($postA, $authorA);
        $reportB = $this->createReport($postB, $authorB);

        $this->authenticateForFilament($this->superAdmin());

        $visibleIds = PostReportResource::getEloquentQuery()->pluck('id')->all();
        $this->assertContains($reportA->id, $visibleIds);
        $this->assertContains($reportB->id, $visibleIds);

        Livewire::test(ListPostReports::class)
            ->assertSuccessful()
            ->assertCanSeeTableRecords([$reportA, $reportB]);
    }

    public function test_super_admin_without_view_permission_cannot_access_list_or_detail(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $super = $this->superAdmin();

        Role::findByName('super-admin', 'web')->revokePermissionTo('posts.reports.view');
        app(PermissionRegistrar::class)->forgetCachedPermissions();

        $this->authenticateForFilament($super->fresh());
        $this->assertFalse(PostReportResource::canViewAny());
        $this->assertFalse(PostReportResource::canView($report));

        Livewire::test(ListPostReports::class)->assertForbidden();
        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])->assertForbidden();
    }

    public function test_user_without_permission_cannot_access_reports(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $this->createReport($post, $author);
        $vecino = User::factory()->create();
        $this->authenticateForFilament($vecino);

        $this->assertFalse(PostReportResource::canViewAny());
        Livewire::test(ListPostReports::class)->assertForbidden();
    }

    public function test_revoked_municipal_membership_blocks_post_reports_on_next_livewire_request(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(ListPostReports::class)->assertSuccessful();

        MunicipalityMember::query()
            ->where('user_id', $admin->id)
            ->firstOrFail()
            ->update(['status' => MunicipalityMemberStatus::Inactive]);

        $this->authenticateForFilament($admin->fresh());
        $this->assertFalse(PostReportResource::canViewAny());
        $this->assertFalse(PostReportResource::canView($report));

        Livewire::test(ListPostReports::class)->assertForbidden();
        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])->assertNotFound();
    }

    public function test_authorized_admin_can_view_report_detail(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $reporter = User::factory()->create(['name' => 'Vecina Reportante']);
        $this->addMemberToGroup($group, $reporter);
        $report = $this->createReport($post, $reporter, [
            'reason_code' => 'spam',
            'details' => 'Publicidad repetida',
        ]);

        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->assertSuccessful()
            ->assertSee('Spam o publicidad no deseada')
            ->assertSee('Publicidad repetida')
            ->assertSee('Título publicado')
            ->assertSee('Cuerpo publicado')
            ->assertSee('Vecina Reportante')
            ->assertSee($author->name);
    }

    public function test_foreign_admin_cannot_open_report_detail_by_id(): void
    {
        [$groupA, $authorA, , $postA] = $this->publishedCommunityPost();
        $reportA = $this->createReport($postA, $authorA);
        [$groupB] = $this->publishedCommunityPost();
        $foreign = $this->municipalAdministratorFor($groupB->municipality);
        $this->authenticateForFilament($foreign);

        $this->assertFalse(PostReportResource::canView($reportA));
        $this->assertNull(PostReportResource::resolveRecordRouteBinding($reportA->getRouteKey()));

        Livewire::test(ViewPostReport::class, ['record' => $reportA->getRouteKey()])
            ->assertNotFound();
    }

    public function test_http_url_for_foreign_report_is_denied(): void
    {
        [$groupA, $authorA, , $postA] = $this->publishedCommunityPost();
        $reportA = $this->createReport($postA, $authorA);
        [$groupB] = $this->publishedCommunityPost();
        $foreign = $this->municipalAdministratorFor($groupB->municipality);
        $this->authenticateForFilament($foreign);

        $this->get(PostReportResource::getUrl('view', ['record' => $reportA]))
            ->assertNotFound();
    }

    public function test_soft_deleted_post_is_readable_in_detail(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author, ['details' => 'Sigue existiendo']);
        $post->delete();
        $this->assertSoftDeleted($post);

        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->assertSuccessful()
            ->assertSee('Publicación eliminada')
            ->assertSee('Título publicado')
            ->assertSee('Sigue existiendo');
    }

    public function test_null_post_id_does_not_error_on_detail(): void
    {
        [$group, $author] = $this->publishedCommunityPost();
        $report = PostReport::query()->create([
            'post_id' => null,
            'municipality_id' => $group->municipality_id,
            'reporter_id' => $author->id,
            'reason_code' => 'inappropriate',
            'status' => PostReportStatus::Open,
        ]);

        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->assertSuccessful()
            ->assertSee('Sin publicación asociada')
            ->assertSee('Publicación no disponible');
    }

    public function test_unknown_reason_code_is_shown_as_original_value(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author, ['reason_code' => 'codigo-desconocido']);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(ListPostReports::class)
            ->assertSee('codigo-desconocido')
            ->assertDontSee('Spam o publicidad no deseada');

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->assertSee('codigo-desconocido');
    }

    public function test_reviewing_resolved_and_dismissed_states_are_visible(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $admin = $this->municipalAdministratorFor($group->municipality);
        $reviewing = $this->createReport($post, $author, ['status' => PostReportStatus::Reviewing, 'resolved_by' => $admin->id]);
        $resolved = $this->createReport($post, $author, [
            'status' => PostReportStatus::Resolved,
            'resolved_by' => $admin->id,
            'resolved_at' => now(),
            'resolution_note' => 'Fundamento de cierre',
        ]);
        $dismissed = $this->createReport($post, $author, [
            'status' => PostReportStatus::Dismissed,
            'resolved_by' => $admin->id,
            'resolved_at' => now(),
            'resolution_note' => 'No procede',
        ]);

        $this->authenticateForFilament($admin);

        Livewire::test(ListPostReports::class)
            ->assertCanSeeTableRecords([$reviewing, $resolved, $dismissed])
            ->assertSee('En revisión')
            ->assertSee('Resuelto')
            ->assertSee('Descartado');

        Livewire::test(ViewPostReport::class, ['record' => $resolved->getRouteKey()])
            ->assertSee('Resuelto')
            ->assertSee('Fundamento de cierre')
            ->assertSee($admin->name);

        Livewire::test(ViewPostReport::class, ['record' => $dismissed->getRouteKey()])
            ->assertSee('Descartado')
            ->assertSee('No procede');
    }

    public function test_resource_forbids_create_edit_and_delete(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        $this->assertFalse(PostReportResource::canCreate());
        $this->assertFalse(PostReportResource::canEdit($report));
        $this->assertFalse(PostReportResource::canDelete($report));
        $this->assertFalse(PostReportResource::canDeleteAny());
        $this->assertFalse(PostReportResource::canForceDelete($report));
        $this->assertFalse(PostReportResource::canForceDeleteAny());
        $this->assertFalse(PostReportResource::canRestore($report));
        $this->assertFalse(PostReportResource::canRestoreAny());
        $this->assertFalse(PostReportResource::canReplicate($report));

        $this->get(PostReportResource::getUrl('index'))->assertSuccessful();
        $this->get(PostReportResource::getUrl('index').'/create')->assertNotFound();
        $this->get(PostReportResource::getUrl('view', ['record' => $report]).'/edit')->assertNotFound();
    }

    public function test_view_page_does_not_mutate_report_status(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author, [
            'status' => PostReportStatus::Reviewing,
            'details' => 'Sin cambios',
        ]);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->assertSuccessful();

        $fresh = $report->fresh();
        $this->assertSame(PostReportStatus::Reviewing, $fresh->status);
        $this->assertNull($fresh->resolved_at);
        $this->assertNull($fresh->resolution_note);
        $this->assertSame('Sin cambios', $fresh->details);
    }

    private function superAdmin(): User
    {
        $user = User::factory()->create();
        $user->assignRole('super-admin');

        return $user->fresh();
    }

    private function createReport($post, User $reporter, array $overrides = []): PostReport
    {
        return PostReport::query()->create(array_merge([
            'post_id' => $post->id,
            'municipality_id' => $post->municipality_id,
            'reporter_id' => $reporter->id,
            'reason_code' => 'inappropriate',
            'status' => PostReportStatus::Open,
        ], $overrides));
    }
}
