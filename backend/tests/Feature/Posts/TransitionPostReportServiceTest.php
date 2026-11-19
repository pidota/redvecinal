<?php

namespace Tests\Feature\Posts;

use App\Domains\Municipality\Enums\MunicipalityMemberRole;
use App\Domains\Municipality\Enums\MunicipalityMemberStatus;
use App\Domains\Municipality\Models\Municipality;
use App\Domains\Municipality\Models\MunicipalityMember;
use App\Domains\Posts\Enums\PostReportStatus;
use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Exceptions\PostDomainException;
use App\Domains\Posts\Models\PostModerationEvent;
use App\Domains\Posts\Models\PostReport;
use App\Domains\Posts\Services\HidePostService;
use App\Domains\Posts\Services\TransitionPostReportService;
use App\Models\User;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Spatie\Permission\Models\Role;
use Spatie\Permission\PermissionRegistrar;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class TransitionPostReportServiceTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    public function test_open_to_reviewing_assigns_actor_without_closing(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);

        $updated = $this->service()->execute(
            $report,
            $admin,
            PostReportStatus::Reviewing,
            'esta nota no debe persistir',
        );

        $this->assertSame(PostReportStatus::Reviewing, $updated->status);
        $this->assertSame($admin->id, $updated->resolved_by);
        $this->assertNull($updated->resolved_at);
        $this->assertNull($updated->resolution_note);
    }

    public function test_open_to_resolved_persists_actor_timestamp_and_note(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        Carbon::setTestNow('2026-11-19 21:15:00');

        $updated = $this->service()->execute($report, $admin, PostReportStatus::Resolved, '  Fundamento válido  ');

        $this->assertSame(PostReportStatus::Resolved, $updated->status);
        $this->assertSame($admin->id, $updated->resolved_by);
        $this->assertTrue($updated->resolved_at->equalTo(Carbon::parse('2026-11-19 21:15:00')));
        $this->assertSame('Fundamento válido', $updated->resolution_note);
        $this->assertSame(PostStatus::Published, $post->fresh()->status);
    }

    public function test_open_to_dismissed_closes_without_hiding_post(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);

        $updated = $this->service()->execute($report, $admin, PostReportStatus::Dismissed, 'No procede');

        $this->assertSame(PostReportStatus::Dismissed, $updated->status);
        $this->assertSame($admin->id, $updated->resolved_by);
        $this->assertNotNull($updated->resolved_at);
        $this->assertSame('No procede', $updated->resolution_note);
        $this->assertSame(PostStatus::Published, $post->fresh()->status);
        $this->assertSame(0, PostModerationEvent::query()->where('post_id', $post->id)->where('event', 'hidden')->count());
    }

    public function test_reviewing_to_resolved(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $taker = $this->municipalAdministratorFor($group->municipality);
        $closer = $this->municipalAdministratorFor($group->municipality);

        $this->service()->execute($report, $taker, PostReportStatus::Reviewing);
        $updated = $this->service()->execute($report->fresh(), $closer, PostReportStatus::Resolved, 'Cierre');

        $this->assertSame(PostReportStatus::Resolved, $updated->status);
        $this->assertSame($closer->id, $updated->resolved_by);
        $this->assertSame('Cierre', $updated->resolution_note);
        $this->assertNotNull($updated->resolved_at);
    }

    public function test_reviewing_to_dismissed(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);

        $this->service()->execute($report, $admin, PostReportStatus::Reviewing);
        $updated = $this->service()->execute($report->fresh(), $admin, PostReportStatus::Dismissed, 'Descartado');

        $this->assertSame(PostReportStatus::Dismissed, $updated->status);
        $this->assertSame('Descartado', $updated->resolution_note);
    }

    public function test_terminal_status_is_immutable(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $closed = $this->service()->execute($report, $admin, PostReportStatus::Resolved, 'Cerrado');

        foreach ([PostReportStatus::Open, PostReportStatus::Reviewing, PostReportStatus::Resolved, PostReportStatus::Dismissed] as $target) {
            try {
                $this->service()->execute($closed->fresh(), $admin, $target, 'Otro fundamento');
                $this->fail('Se esperaba excepción de dominio para estado terminal.');
            } catch (PostDomainException $exception) {
                $this->assertSame('Transición de reporte no permitida.', $exception->getMessage());
            }
        }

        $fresh = $closed->fresh();
        $this->assertSame(PostReportStatus::Resolved, $fresh->status);
        $this->assertSame($admin->id, $fresh->resolved_by);
        $this->assertSame('Cerrado', $fresh->resolution_note);
    }

    public function test_repeated_transition_to_same_open_or_reviewing_status_is_rejected(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);

        $this->expectException(PostDomainException::class);
        $this->service()->execute($report, $admin, PostReportStatus::Open);
    }

    public function test_reviewing_to_reviewing_is_rejected(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $reviewing = $this->service()->execute($report, $admin, PostReportStatus::Reviewing);

        $this->expectException(PostDomainException::class);
        $this->service()->execute($reviewing, $admin, PostReportStatus::Reviewing);
    }

    public function test_reviewing_cannot_return_to_open(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $reviewing = $this->service()->execute($report, $admin, PostReportStatus::Reviewing);

        $this->expectException(PostDomainException::class);
        $this->service()->execute($reviewing, $admin, PostReportStatus::Open);
    }

    public function test_resolution_note_is_required_to_close(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);

        try {
            $this->service()->execute($report, $admin, PostReportStatus::Resolved, null);
            $this->fail('Se esperaba fundamento obligatorio.');
        } catch (PostDomainException $exception) {
            $this->assertSame('El fundamento de resolución es obligatorio.', $exception->getMessage());
        }

        $this->assertSame(PostReportStatus::Open, $report->fresh()->status);
        $this->assertNull($report->fresh()->resolved_by);
    }

    public function test_blank_resolution_note_is_rejected(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);

        $this->expectException(PostDomainException::class);
        $this->service()->execute($report, $admin, PostReportStatus::Dismissed, "  \n\t  ");
    }

    public function test_oversized_resolution_note_is_rejected_without_truncation(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $note = str_repeat('a', TransitionPostReportService::RESOLUTION_NOTE_MAX_LENGTH + 1);

        try {
            $this->service()->execute($report, $admin, PostReportStatus::Resolved, $note);
            $this->fail('Se esperaba rechazo por longitud.');
        } catch (PostDomainException) {
            // expected
        }

        $fresh = $report->fresh();
        $this->assertSame(PostReportStatus::Open, $fresh->status);
        $this->assertNull($fresh->resolution_note);
    }

    public function test_resolution_note_at_max_length_is_accepted(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $note = str_repeat('b', TransitionPostReportService::RESOLUTION_NOTE_MAX_LENGTH);

        $updated = $this->service()->execute($report, $admin, PostReportStatus::Resolved, $note);

        $this->assertSame($note, $updated->resolution_note);
    }

    public function test_second_officer_cannot_overwrite_a_closed_report(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $first = $this->municipalAdministratorFor($group->municipality);
        $second = $this->municipalAdministratorFor($group->municipality);

        $this->service()->execute($report, $first, PostReportStatus::Resolved, 'Primero');

        try {
            $this->service()->execute($report->fresh(), $second, PostReportStatus::Dismissed, 'Segundo');
            $this->fail('El segundo funcionario no debe poder cerrar de nuevo.');
        } catch (PostDomainException $exception) {
            $this->assertSame('Transición de reporte no permitida.', $exception->getMessage());
        }

        $fresh = $report->fresh();
        $this->assertSame(PostReportStatus::Resolved, $fresh->status);
        $this->assertSame($first->id, $fresh->resolved_by);
        $this->assertSame('Primero', $fresh->resolution_note);
    }

    public function test_stale_eloquent_instance_cannot_apply_obsolete_transition(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $stale = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);

        $this->service()->execute($stale, $admin, PostReportStatus::Resolved, 'Estado real cerrado');
        $this->assertSame(PostReportStatus::Open, $stale->status);

        try {
            $this->service()->execute($stale, $admin, PostReportStatus::Reviewing);
            $this->fail('La instancia obsoleta no debe transicionar.');
        } catch (PostDomainException) {
            // expected
        }

        $fresh = $stale->fresh();
        $this->assertSame(PostReportStatus::Resolved, $fresh->status);
        $this->assertSame('Estado real cerrado', $fresh->resolution_note);
        $this->assertSame($admin->id, $fresh->resolved_by);
    }

    public function test_in_memory_municipality_id_does_not_bypass_authorization(): void
    {
        [$groupA, $author, , $postA] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($postA, $author);
        $foreignMunicipality = Municipality::factory()->create();
        $foreignAdmin = $this->municipalAdministratorFor($foreignMunicipality);

        $report->municipality_id = $foreignMunicipality->id;

        $this->expectException(AuthorizationException::class);
        $this->service()->execute($report, $foreignAdmin, PostReportStatus::Reviewing);
    }

    public function test_foreign_municipal_admin_cannot_transition(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $foreign = $this->municipalAdministratorFor(Municipality::factory()->create());

        $this->expectException(AuthorizationException::class);
        $this->service()->execute($report, $foreign, PostReportStatus::Resolved, 'Ajeno');
    }

    public function test_revoked_membership_cannot_transition(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);

        MunicipalityMember::query()
            ->where('user_id', $admin->id)
            ->firstOrFail()
            ->update(['status' => MunicipalityMemberStatus::Inactive]);

        $this->expectException(AuthorizationException::class);
        $this->service()->execute($report, $admin->fresh(), PostReportStatus::Reviewing);
    }

    public function test_non_admin_municipal_member_cannot_transition(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $funcionario = User::factory()->create();
        MunicipalityMember::factory()->create([
            'municipality_id' => $group->municipality_id,
            'user_id' => $funcionario->id,
            'role' => MunicipalityMemberRole::Funcionario,
            'status' => MunicipalityMemberStatus::Active,
        ]);
        $funcionario->givePermissionTo(['posts.reports.view', 'posts.reports.resolve']);

        $this->expectException(AuthorizationException::class);
        $this->service()->execute($report, $funcionario, PostReportStatus::Resolved, 'Sin cargo');
    }

    public function test_super_admin_can_transition_any_municipality_report(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $super = User::factory()->create();
        $super->assignRole('super-admin');

        $updated = $this->service()->execute($report, $super->fresh(), PostReportStatus::Resolved, 'Global');

        $this->assertSame(PostReportStatus::Resolved, $updated->status);
        $this->assertSame($super->id, $updated->resolved_by);
    }

    public function test_super_admin_without_resolve_permission_is_denied(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $super = User::factory()->create();
        $super->assignRole('super-admin');
        Role::findByName('super-admin', 'web')->revokePermissionTo('posts.reports.resolve');
        app(PermissionRegistrar::class)->forgetCachedPermissions();

        $this->expectException(AuthorizationException::class);
        $this->service()->execute($report, $super->fresh(), PostReportStatus::Resolved, 'Sin permiso');
    }

    public function test_user_without_permission_cannot_transition(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);

        $this->expectException(AuthorizationException::class);
        $this->service()->execute($report, $moderator, PostReportStatus::Reviewing);
    }

    public function test_hidden_post_report_can_be_resolved_without_changing_the_post(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);

        app(HidePostService::class)->execute($post->fresh(), $moderator, 'Moderación previa');
        $hidden = $post->fresh();
        $this->assertSame(PostStatus::Hidden, $hidden->status);
        $hiddenAt = $hidden->hidden_at?->toJSON();
        $hideEvents = PostModerationEvent::query()->where('post_id', $post->id)->where('event', 'hidden')->count();

        $updated = $this->service()->execute($report, $admin, PostReportStatus::Resolved, 'Ya estaba oculta');

        $this->assertSame(PostReportStatus::Resolved, $updated->status);
        $stillHidden = $post->fresh();
        $this->assertSame(PostStatus::Hidden, $stillHidden->status);
        $this->assertSame($hiddenAt, $stillHidden->hidden_at?->toJSON());
        $this->assertSame(
            $hideEvents,
            PostModerationEvent::query()->where('post_id', $post->id)->where('event', 'hidden')->count()
        );
    }

    public function test_soft_deleted_post_report_can_be_resolved_without_restoring_the_post(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);

        $post->delete();
        $this->assertSoftDeleted($post);

        $updated = $this->service()->execute($report, $admin, PostReportStatus::Dismissed, 'Publicación eliminada');

        $this->assertSame(PostReportStatus::Dismissed, $updated->status);
        $this->assertSame($post->id, $updated->post_id);
        $this->assertSoftDeleted($post);
    }

    public function test_transition_does_not_hide_or_create_hidden_events(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $hiddenBefore = PostModerationEvent::query()->where('post_id', $post->id)->where('event', 'hidden')->count();

        $this->service()->execute($report, $admin, PostReportStatus::Resolved, 'Sin ocultar');

        $this->assertSame(PostStatus::Published, $post->fresh()->status);
        $this->assertSame(
            $hiddenBefore,
            PostModerationEvent::query()->where('post_id', $post->id)->where('event', 'hidden')->count()
        );
        $this->assertSame(
            1,
            PostModerationEvent::query()
                ->where('post_id', $post->id)
                ->where('event', TransitionPostReportService::EVENT_RESOLVED)
                ->count()
        );
    }

    public function test_rejected_transition_rolls_back_without_mutating(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $snapshot = $report->only(['status', 'resolved_by', 'resolved_at', 'resolution_note', 'updated_at']);

        try {
            $this->service()->execute($report, $admin, PostReportStatus::Resolved, '   ');
            $this->fail('Se esperaba rechazo.');
        } catch (PostDomainException) {
            // expected
        }

        $fresh = $report->fresh();
        $this->assertSame(PostReportStatus::Open, $fresh->status);
        $this->assertNull($fresh->resolved_by);
        $this->assertNull($fresh->resolved_at);
        $this->assertNull($fresh->resolution_note);
        $this->assertTrue($fresh->updated_at->equalTo($snapshot['updated_at']));
    }

    /**
     * La prueba precedente cubre dos llamadas secuenciales, no dos conexiones
     * MySQL compitiendo por lockForUpdate. phpunit.mysql.xml no incluye este
     * directorio; un test de bloqueo real queda fuera de 5D.2.
     */
    public function test_sequential_second_closer_loses_without_last_write_wins(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $first = $this->municipalAdministratorFor($group->municipality);
        $second = $this->municipalAdministratorFor($group->municipality);

        $this->service()->execute($report, $first, PostReportStatus::Dismissed, 'Gana el primero');

        $this->expectException(PostDomainException::class);
        $this->service()->execute($report, $second, PostReportStatus::Resolved, 'No debe quedar');
    }

    private function service(): TransitionPostReportService
    {
        return app(TransitionPostReportService::class);
    }

    private function createOpenReport($post, User $reporter): PostReport
    {
        return PostReport::query()->create([
            'post_id' => $post->id,
            'municipality_id' => $post->municipality_id,
            'reporter_id' => $reporter->id,
            'reason_code' => 'spam',
            'status' => PostReportStatus::Open,
        ]);
    }
}
