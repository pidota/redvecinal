<?php

namespace Tests\Feature\Posts\Filament;

use App\Domains\Municipality\Enums\MunicipalityMemberStatus;
use App\Domains\Municipality\Models\MunicipalityMember;
use App\Domains\Posts\Enums\PostReportStatus;
use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Exceptions\PostDomainException;
use App\Domains\Posts\Models\PostModerationEvent;
use App\Domains\Posts\Models\PostReport;
use App\Domains\Posts\Services\HidePostService;
use App\Domains\Posts\Services\TransitionPostReportService;
use App\Filament\Resources\PostReports\Pages\ListPostReports;
use App\Filament\Resources\PostReports\Pages\ViewPostReport;
use App\Models\User;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use InvalidArgumentException;
use Livewire\Livewire;
use Mockery\MockInterface;
use Spatie\Permission\Models\Role;
use Spatie\Permission\PermissionRegistrar;
use Symfony\Component\HttpKernel\Exception\HttpException;
use Tests\Concerns\CreatesPostFixtures;
use Tests\Concerns\InteractsWithFilamentPanel;
use Tests\TestCase;

class PostReportFilamentActionsTest extends TestCase
{
    use CreatesPostFixtures, InteractsWithFilamentPanel, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
        Role::findOrCreate('super-admin', 'web');
        Role::findOrCreate('administrador-municipal', 'web');
    }

    public function test_authorized_admin_sees_review_action_on_open_report(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $this->authenticateForFilament($this->municipalAdministratorFor($group->municipality));

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->assertSuccessful()
            ->assertActionVisible('reviewReport')
            ->assertActionVisible('resolveReport')
            ->assertActionVisible('dismissReport');
    }

    public function test_authorized_admin_can_take_open_report_into_review(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->callAction('reviewReport')
            ->assertNotified('Reporte tomado en revisión')
            ->assertSee('En revisión');

        $fresh = $report->fresh();
        $this->assertSame(PostReportStatus::Reviewing, $fresh->status);
        $this->assertSame($admin->id, $fresh->resolved_by);
        $this->assertNull($fresh->resolved_at);
        $this->assertNull($fresh->resolution_note);
        $this->assertSame(PostStatus::Published, $post->fresh()->status);
    }

    public function test_authorized_admin_can_resolve_directly_from_open(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->callAction('resolveReport', ['resolution_note' => '  Contenido verificado  '])
            ->assertHasNoFormErrors()
            ->assertNotified('Reporte resuelto')
            ->assertSee('Resuelto')
            ->assertSee('Contenido verificado')
            ->assertSee($admin->name)
            ->assertSee(now()->format('d/m/Y'));

        $fresh = $report->fresh();
        $this->assertSame(PostReportStatus::Resolved, $fresh->status);
        $this->assertSame($admin->id, $fresh->resolved_by);
        $this->assertNotNull($fresh->resolved_at);
        $this->assertSame('Contenido verificado', $fresh->resolution_note);
        $this->assertSame(PostStatus::Published, $post->fresh()->status);
        $this->assertSame(0, PostModerationEvent::query()->where('post_id', $post->id)->where('event', 'hidden')->count());
    }

    public function test_authorized_admin_can_dismiss_directly_from_open(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->callAction('dismissReport', ['resolution_note' => 'No constituye infracción'])
            ->assertNotified('Reporte descartado')
            ->assertSee('Descartado');

        $fresh = $report->fresh();
        $this->assertSame(PostReportStatus::Dismissed, $fresh->status);
        $this->assertSame('No constituye infracción', $fresh->resolution_note);
        $this->assertDatabaseHas('post_reports', ['id' => $report->id]);
        $this->assertSame(PostStatus::Published, $post->fresh()->status);
    }

    public function test_authorized_admin_can_resolve_from_reviewing(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        app(TransitionPostReportService::class)->execute($report, $admin, PostReportStatus::Reviewing);

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->assertActionHidden('reviewReport')
            ->assertActionVisible('resolveReport')
            ->callAction('resolveReport', ['resolution_note' => 'Procede sanción editorial'])
            ->assertNotified('Reporte resuelto');

        $this->assertSame(PostReportStatus::Resolved, $report->fresh()->status);
    }

    public function test_authorized_admin_can_dismiss_from_reviewing(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        app(TransitionPostReportService::class)->execute($report, $admin, PostReportStatus::Reviewing);

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->callAction('dismissReport', ['resolution_note' => 'Falsa alarma'])
            ->assertNotified('Reporte descartado');

        $this->assertSame(PostReportStatus::Dismissed, $report->fresh()->status);
    }

    public function test_empty_resolution_note_is_rejected_without_mutation(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $this->authenticateForFilament($this->municipalAdministratorFor($group->municipality));

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->callAction('resolveReport', ['resolution_note' => ''])
            ->assertHasFormErrors(['resolution_note'])
            ->assertNotNotified('Reporte resuelto');

        $this->assertSame(PostReportStatus::Open, $report->fresh()->status);
        $this->assertNull($report->fresh()->resolution_note);
    }

    public function test_blank_resolution_note_is_rejected_without_mutation(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $this->authenticateForFilament($this->municipalAdministratorFor($group->municipality));

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->callAction('dismissReport', ['resolution_note' => "  \n\t  "])
            ->assertHasFormErrors(['resolution_note'])
            ->assertNotNotified('Reporte descartado');

        $this->assertSame(PostReportStatus::Open, $report->fresh()->status);
    }

    public function test_oversized_resolution_note_is_rejected_without_mutation(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $this->authenticateForFilament($this->municipalAdministratorFor($group->municipality));
        $note = str_repeat('a', TransitionPostReportService::RESOLUTION_NOTE_MAX_LENGTH + 1);

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->callAction('resolveReport', ['resolution_note' => $note])
            ->assertHasFormErrors(['resolution_note'])
            ->assertNotNotified('Reporte resuelto');

        $this->assertSame(PostReportStatus::Open, $report->fresh()->status);
        $this->assertNull($report->fresh()->resolution_note);
    }

    public function test_valid_resolution_note_is_persisted_trimmed(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $this->authenticateForFilament($this->municipalAdministratorFor($group->municipality));
        $note = str_repeat('b', TransitionPostReportService::RESOLUTION_NOTE_MAX_LENGTH);

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->callAction('resolveReport', ['resolution_note' => $note])
            ->assertHasNoFormErrors()
            ->assertNotified('Reporte resuelto');

        $this->assertSame($note, $report->fresh()->resolution_note);
    }

    public function test_terminal_reports_hide_management_actions(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);
        $resolved = $this->createReport($post, $author, [
            'status' => PostReportStatus::Resolved,
            'resolved_by' => $admin->id,
            'resolved_at' => now(),
            'resolution_note' => 'Cerrado',
        ]);

        Livewire::test(ViewPostReport::class, ['record' => $resolved->getRouteKey()])
            ->assertActionDoesNotExist('edit')
            ->assertActionHidden('reviewReport')
            ->assertActionHidden('resolveReport')
            ->assertActionHidden('dismissReport');

        $dismissed = $this->createReport($post, $author, [
            'status' => PostReportStatus::Dismissed,
            'resolved_by' => $admin->id,
            'resolved_at' => now(),
            'resolution_note' => 'Descartado',
        ]);

        Livewire::test(ViewPostReport::class, ['record' => $dismissed->getRouteKey()])
            ->assertActionHidden('reviewReport')
            ->assertActionHidden('resolveReport')
            ->assertActionHidden('dismissReport');
    }

    public function test_user_without_resolve_permission_cannot_execute_actions(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        Role::findByName('administrador-municipal', 'web')->revokePermissionTo('posts.reports.resolve');
        app(PermissionRegistrar::class)->forgetCachedPermissions();
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        $livewire = Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->assertSuccessful()
            ->assertActionHidden('reviewReport')
            ->assertActionHidden('resolveReport')
            ->assertActionHidden('dismissReport');

        $livewire->call('mountAction', 'resolveReport');
        $livewire->call('callMountedAction');

        $this->assertSame(PostReportStatus::Open, $report->fresh()->status);
        $this->assertNull($report->fresh()->resolved_by);
    }

    public function test_foreign_admin_cannot_execute_actions_on_another_municipality_report(): void
    {
        [$groupA, $authorA, , $postA] = $this->publishedCommunityPost();
        $reportA = $this->createReport($postA, $authorA);
        [$groupB] = $this->publishedCommunityPost();
        $this->authenticateForFilament($this->municipalAdministratorFor($groupB->municipality));

        Livewire::test(ViewPostReport::class, ['record' => $reportA->getRouteKey()])
            ->assertNotFound();

        $this->assertSame(PostReportStatus::Open, $reportA->fresh()->status);
    }

    public function test_spatie_permission_revoked_before_confirm_denies_without_mutation(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        $livewire = Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->assertActionVisible('resolveReport')
            ->mountAction('resolveReport');

        Role::findByName('administrador-municipal', 'web')->revokePermissionTo('posts.reports.resolve');
        app(PermissionRegistrar::class)->forgetCachedPermissions();
        $this->authenticateForFilament($admin->fresh());

        $livewire
            ->fillForm(['resolution_note' => 'Permiso revocado'])
            ->callMountedAction()
            ->assertNotNotified('Reporte resuelto');

        $this->assertSame(PostReportStatus::Open, $report->fresh()->status);
        $this->assertNull($report->fresh()->resolved_by);
        $this->assertNull($report->fresh()->resolution_note);
    }

    public function test_null_post_id_can_be_resolved_without_server_error(): void
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
            ->callAction('resolveReport', ['resolution_note' => 'Sin publicación asociada'])
            ->assertNotified('Reporte resuelto');

        $fresh = $report->fresh();
        $this->assertSame(PostReportStatus::Resolved, $fresh->status);
        $this->assertNull($fresh->post_id);
        $this->assertSame('Sin publicación asociada', $fresh->resolution_note);
        $this->assertSame(
            0,
            PostModerationEvent::query()->get()->filter(
                fn (PostModerationEvent $event): bool => ($event->payload['report_id'] ?? null) === $report->id
            )->count()
        );
    }

    public function test_soft_deleted_post_report_can_be_resolved_from_filament(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $post->delete();
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->assertSuccessful()
            ->callAction('dismissReport', ['resolution_note' => 'Publicación ya eliminada'])
            ->assertNotified('Reporte descartado');

        $this->assertSame(PostReportStatus::Dismissed, $report->fresh()->status);
        $this->assertSoftDeleted($post);
        $this->assertSame(
            1,
            PostModerationEvent::query()
                ->where('post_id', $post->id)
                ->where('event', TransitionPostReportService::EVENT_DISMISSED)
                ->count()
        );
    }

    public function test_revoked_membership_before_confirm_denies_without_mutation(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        $livewire = Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->assertActionVisible('resolveReport')
            ->mountAction('resolveReport');

        MunicipalityMember::query()
            ->where('user_id', $admin->id)
            ->firstOrFail()
            ->update(['status' => MunicipalityMemberStatus::Inactive]);

        $this->authenticateForFilament($admin->fresh());

        try {
            $livewire
                ->fillForm(['resolution_note' => 'Tarde'])
                ->callMountedAction();

            $livewire->assertNotNotified('Reporte resuelto');
        } catch (InvalidArgumentException $exception) {
            $this->assertStringContainsString('Invalid Livewire snapshot', $exception->getMessage());
        } catch (HttpException $exception) {
            $this->assertContains($exception->getStatusCode(), [403, 404]);
        }

        $this->assertSame(PostReportStatus::Open, $report->fresh()->status);
        $this->assertNull($report->fresh()->resolved_by);
        $this->assertNull($report->fresh()->resolution_note);

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->assertNotFound();
    }

    public function test_stale_open_view_cannot_overwrite_after_status_changed(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $first = $this->municipalAdministratorFor($group->municipality);
        $second = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($second);

        $livewire = Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->assertActionVisible('resolveReport');

        app(TransitionPostReportService::class)->execute($report, $first, PostReportStatus::Resolved, 'Gana el primero');

        $livewire->callAction('resolveReport', ['resolution_note' => 'Intento tardío'])
            ->assertNotNotified('Reporte resuelto');

        $fresh = $report->fresh();
        $this->assertSame(PostReportStatus::Resolved, $fresh->status);
        $this->assertSame($first->id, $fresh->resolved_by);
        $this->assertSame('Gana el primero', $fresh->resolution_note);
    }

    public function test_sequential_filament_closures_first_officer_wins(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $first = $this->municipalAdministratorFor($group->municipality);
        $second = $this->municipalAdministratorFor($group->municipality);

        $this->authenticateForFilament($first);
        $firstPage = Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()]);

        $this->authenticateForFilament($second);
        $secondPage = Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()]);

        $this->authenticateForFilament($first);
        $firstPage->callAction('resolveReport', ['resolution_note' => 'Primero']);

        $this->authenticateForFilament($second);
        $secondPage->callAction('dismissReport', ['resolution_note' => 'Segundo'])
            ->assertNotNotified('Reporte descartado');

        $fresh = $report->fresh();
        $this->assertSame(PostReportStatus::Resolved, $fresh->status);
        $this->assertSame($first->id, $fresh->resolved_by);
        $this->assertSame('Primero', $fresh->resolution_note);
        $this->assertNotEquals($second->id, $fresh->resolved_by);
    }

    public function test_actions_do_not_hide_or_change_the_post(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        $this->mock(HidePostService::class, function ($mock): void {
            $mock->shouldNotReceive('execute');
        });

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->callAction('resolveReport', ['resolution_note' => 'Sin ocultar']);

        $this->assertSame(PostStatus::Published, $post->fresh()->status);
        $this->assertSame(0, PostModerationEvent::query()->where('post_id', $post->id)->where('event', 'hidden')->count());
    }

    public function test_list_page_has_no_bulk_or_inline_status_actions(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $this->createReport($post, $author);
        $this->authenticateForFilament($this->municipalAdministratorFor($group->municipality));

        $livewire = Livewire::test(ListPostReports::class)
            ->assertSuccessful()
            ->assertActionDoesNotExist('reviewReport')
            ->assertActionDoesNotExist('resolveReport')
            ->assertActionDoesNotExist('dismissReport')
            ->assertActionDoesNotExist('edit');

        $this->assertSame([], $livewire->instance()->getTable()->getToolbarActions());
    }

    public function test_authorization_exception_shows_safe_error_without_mutation(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $this->authenticateForFilament($this->municipalAdministratorFor($group->municipality));
        $this->mockTransitionServiceThrowing(new AuthorizationException('hidden internals'));

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->callAction('reviewReport')
            ->assertNotified('No tienes autorización para gestionar este reporte.')
            ->assertNotNotified('Reporte tomado en revisión');

        $this->assertSame(PostReportStatus::Open, $report->fresh()->status);
    }

    public function test_domain_exception_shows_controlled_error_without_success(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $this->authenticateForFilament($this->municipalAdministratorFor($group->municipality));
        $this->mockTransitionServiceThrowing(new PostDomainException('Transición de reporte no permitida.'));

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->callAction('resolveReport', ['resolution_note' => 'Intento concurrente'])
            ->assertNotified('El reporte cambió de estado o la transición no está permitida. Actualiza la página.')
            ->assertNotNotified('Reporte resuelto');

        $this->assertSame(PostReportStatus::Open, $report->fresh()->status);
        $this->assertNull($report->fresh()->resolution_note);
    }

    public function test_unexpected_error_does_not_show_success_or_mutate(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $this->authenticateForFilament($this->municipalAdministratorFor($group->municipality));
        $this->mockTransitionServiceThrowing(new \RuntimeException('fallo interno'));

        try {
            Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
                ->callAction('reviewReport');
            $this->fail('El error inesperado debe propagarse sin convertirse en éxito.');
        } catch (\RuntimeException $exception) {
            $this->assertSame('fallo interno', $exception->getMessage());
        }

        $this->assertSame(PostReportStatus::Open, $report->fresh()->status);
        $this->assertNull($report->fresh()->resolved_by);
    }

    public function test_super_admin_with_permission_can_resolve(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $super = User::factory()->create();
        $super->assignRole('super-admin');
        $this->authenticateForFilament($super->fresh());

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->callAction('resolveReport', ['resolution_note' => 'Supervisión global'])
            ->assertNotified('Reporte resuelto');

        $this->assertSame(PostReportStatus::Resolved, $report->fresh()->status);
        $this->assertSame($super->id, $report->fresh()->resolved_by);
    }

    public function test_super_admin_without_resolve_permission_cannot_manage(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createReport($post, $author);
        $super = User::factory()->create();
        $super->assignRole('super-admin');
        Role::findByName('super-admin', 'web')->revokePermissionTo('posts.reports.resolve');
        app(PermissionRegistrar::class)->forgetCachedPermissions();
        $this->authenticateForFilament($super->fresh());

        Livewire::test(ViewPostReport::class, ['record' => $report->getRouteKey()])
            ->assertSuccessful()
            ->assertActionHidden('reviewReport')
            ->assertActionHidden('resolveReport')
            ->assertActionHidden('dismissReport')
            ->call('mountAction', 'resolveReport')
            ->call('callMountedAction');

        $this->assertSame(PostReportStatus::Open, $report->fresh()->status);
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

    private function mockTransitionServiceThrowing(\Throwable $exception): void
    {
        $real = app(TransitionPostReportService::class);

        $this->mock(TransitionPostReportService::class, function (MockInterface $mock) use ($real, $exception): void {
            $mock->shouldReceive('isAllowedTransition')
                ->andReturnUsing(
                    fn (PostReportStatus $from, PostReportStatus $to): bool => $real->isAllowedTransition($from, $to)
                );
            $mock->shouldReceive('execute')->once()->andThrow($exception);
        });
    }
}
