<?php

namespace Tests\Feature\Posts;

use App\Domains\Municipality\Enums\MunicipalityMemberRole;
use App\Domains\Municipality\Enums\MunicipalityMemberStatus;
use App\Domains\Municipality\Models\Municipality;
use App\Domains\Municipality\Models\MunicipalityMember;
use App\Domains\Posts\Enums\PostCommentStatus;
use App\Domains\Posts\Enums\PostReportStatus;
use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Exceptions\PostDomainException;
use App\Domains\Posts\Models\PostComment;
use App\Domains\Posts\Models\PostModerationEvent;
use App\Domains\Posts\Models\PostReport;
use App\Domains\Posts\Services\TransitionPostReportService;
use App\Domains\Posts\Support\PostModerationEventRecorder;
use App\Models\User;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Collection;
use RuntimeException;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class PostReportAuditTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_valid_transition_creates_exactly_one_event(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $before = PostModerationEvent::query()->count();

        $this->service()->execute($report, $admin, PostReportStatus::Reviewing);

        $events = $this->eventsForReport($report);
        $this->assertCount(1, $events);
        $this->assertSame(TransitionPostReportService::EVENT_REVIEWING, $events->first()->event);
        $this->assertSame($before + 1, PostModerationEvent::query()->count());
    }

    public function test_event_contains_correct_actor_municipality_statuses_and_report(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author, [
            'details' => 'Datos del vecino reportante',
        ]);
        $admin = $this->municipalAdministratorFor($group->municipality);

        $this->service()->execute($report, $admin, PostReportStatus::Resolved, 'Fundamento interno');

        $event = $this->eventsForReport($report)->first();
        $this->assertNotNull($event);
        $this->assertSame($admin->id, $event->actor_user_id);
        $this->assertSame($report->municipality_id, $event->municipality_id);
        $this->assertSame($post->id, $event->post_id);
        $this->assertSame(PostReportStatus::Open->value, $event->from_status);
        $this->assertSame(PostReportStatus::Resolved->value, $event->to_status);
        $this->assertSame(TransitionPostReportService::EVENT_RESOLVED, $event->event);
        $this->assertSame(['report_id' => $report->id], $event->payload);
        $this->assertNotNull($event->created_at);
    }

    public function test_payload_does_not_contain_unnecessary_personal_or_duplicate_data(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $author->forceFill(['email' => 'reportante-audit@example.test', 'name' => 'Nombre Reportante Único'])->save();
        $report = $this->createOpenReport($post, $author->fresh(), [
            'details' => 'Teléfono 912345678 y dirección secreta',
        ]);
        $admin = $this->municipalAdministratorFor($group->municipality);

        $this->service()->execute($report, $admin, PostReportStatus::Dismissed, 'Fundamento que no debe copiarse');

        $encoded = json_encode($this->eventsForReport($report)->first()->payload);
        $this->assertIsString($encoded);
        $this->assertStringNotContainsString('reportante-audit@example.test', $encoded);
        $this->assertStringNotContainsString('Nombre Reportante Único', $encoded);
        $this->assertStringNotContainsString('912345678', $encoded);
        $this->assertStringNotContainsString('dirección secreta', $encoded);
        $this->assertStringNotContainsString('Fundamento que no debe copiarse', $encoded);
        $this->assertStringNotContainsString('reporter_id', $encoded);
        $this->assertStringNotContainsString('resolution_note', $encoded);
        $this->assertStringNotContainsString('details', $encoded);
    }

    public function test_invalid_transition_does_not_create_events(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $before = PostModerationEvent::query()->count();

        try {
            $this->service()->execute($report, $admin, PostReportStatus::Open);
            $this->fail('Se esperaba transición inválida.');
        } catch (PostDomainException) {
            // expected
        }

        $this->assertSame($before, PostModerationEvent::query()->count());
        $this->assertSame(PostReportStatus::Open, $report->fresh()->status);
    }

    public function test_denied_authorization_does_not_create_events(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $foreign = $this->municipalAdministratorFor(Municipality::factory()->create());
        $before = PostModerationEvent::query()->count();

        try {
            $this->service()->execute($report, $foreign, PostReportStatus::Resolved, 'Ajeno');
            $this->fail('Se esperaba denegación.');
        } catch (AuthorizationException) {
            // expected
        }

        $this->assertSame($before, PostModerationEvent::query()->count());
        $this->assertSame(PostReportStatus::Open, $report->fresh()->status);
    }

    public function test_rejected_second_close_does_not_create_another_event(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $first = $this->municipalAdministratorFor($group->municipality);
        $second = $this->municipalAdministratorFor($group->municipality);

        $this->service()->execute($report, $first, PostReportStatus::Resolved, 'Primero');
        $this->assertCount(1, $this->eventsForReport($report));

        try {
            $this->service()->execute($report->fresh(), $second, PostReportStatus::Dismissed, 'Segundo');
            $this->fail('El segundo cierre debe rechazarse.');
        } catch (PostDomainException) {
            // expected
        }

        $events = $this->eventsForReport($report);
        $this->assertCount(1, $events);
        $this->assertSame(TransitionPostReportService::EVENT_RESOLVED, $events->first()->event);
        $this->assertSame($first->id, $events->first()->actor_user_id);
        $this->assertSame(PostReportStatus::Resolved, $report->fresh()->status);
        $this->assertSame('Primero', $report->fresh()->resolution_note);
    }

    public function test_audit_recorder_failure_rolls_back_status_and_event(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);

        $this->mock(PostModerationEventRecorder::class, function ($mock): void {
            $mock->shouldReceive('record')->once()->andThrow(new RuntimeException('fallo de auditoría'));
        });

        try {
            app(TransitionPostReportService::class)->execute(
                $report,
                $admin,
                PostReportStatus::Resolved,
                'No debe persistir',
            );
            $this->fail('Se esperaba excepción del recorder.');
        } catch (RuntimeException $exception) {
            $this->assertSame('fallo de auditoría', $exception->getMessage());
        }

        $fresh = $report->fresh();
        $this->assertSame(PostReportStatus::Open, $fresh->status);
        $this->assertNull($fresh->resolved_by);
        $this->assertNull($fresh->resolved_at);
        $this->assertNull($fresh->resolution_note);
        $this->assertCount(0, $this->eventsForReport($report));
        $this->assertSame(PostStatus::Published, $post->fresh()->status);
    }

    public function test_soft_deleted_post_keeps_audit_trace(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $post->delete();
        $this->assertSoftDeleted($post);

        $this->service()->execute($report, $admin, PostReportStatus::Dismissed, 'Publicación eliminada');

        $event = $this->eventsForReport($report)->first();
        $this->assertNotNull($event);
        $this->assertSame($post->id, $event->post_id);
        $this->assertSame(TransitionPostReportService::EVENT_DISMISSED, $event->event);
        $this->assertSame($admin->id, $event->actor_user_id);
        $this->assertSoftDeleted($post);
        $this->assertSame($post->id, $report->fresh()->post_id);
    }

    public function test_null_post_id_transitions_without_inventing_audit_or_failing(): void
    {
        [$group, $author] = $this->publishedCommunityPost();
        $report = PostReport::query()->create([
            'post_id' => null,
            'municipality_id' => $group->municipality_id,
            'reporter_id' => $author->id,
            'reason_code' => 'inappropriate',
            'details' => 'Sin publicación',
            'status' => PostReportStatus::Open,
        ]);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $before = PostModerationEvent::query()->count();

        $updated = $this->service()->execute($report, $admin, PostReportStatus::Resolved, 'Cierre sin post');

        $this->assertSame(PostReportStatus::Resolved, $updated->status);
        $this->assertNull($updated->post_id);
        $this->assertSame($admin->id, $updated->resolved_by);
        $this->assertSame('Cierre sin post', $updated->resolution_note);
        $this->assertSame($before, PostModerationEvent::query()->count());
        $this->assertCount(0, $this->eventsForReport($report));
    }

    public function test_comment_only_report_without_post_id_is_partially_traceable(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $comment = PostComment::query()->create([
            'post_id' => $post->id,
            'municipality_id' => $post->municipality_id,
            'author_id' => $author->id,
            'body' => 'Comentario reportado',
            'status' => PostCommentStatus::Visible,
        ]);
        $report = PostReport::query()->create([
            'post_id' => null,
            'post_comment_id' => $comment->id,
            'municipality_id' => $group->municipality_id,
            'reporter_id' => $author->id,
            'reason_code' => 'inappropriate',
            'status' => PostReportStatus::Open,
        ]);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $before = PostModerationEvent::query()->where('post_id', $post->id)->count();

        $updated = $this->service()->execute($report, $admin, PostReportStatus::Dismissed, 'Solo comentario');

        $this->assertSame(PostReportStatus::Dismissed, $updated->status);
        $this->assertNull($updated->post_id);
        $this->assertSame($comment->id, $updated->post_comment_id);
        $this->assertSame($before, PostModerationEvent::query()->where('post_id', $post->id)->count());
        $this->assertCount(0, $this->eventsForReport($report));
        $this->assertSame(PostStatus::Published, $post->fresh()->status);
    }

    public function test_physically_deleted_post_nulls_post_id_and_does_not_500(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $postId = $post->id;
        $post->forceDelete();

        $freshReport = $report->fresh();
        $this->assertNull($freshReport->post_id);

        $updated = $this->service()->execute($freshReport, $admin, PostReportStatus::Resolved, 'Post borrado físico');

        $this->assertSame(PostReportStatus::Resolved, $updated->status);
        $this->assertNull($updated->post_id);
        $this->assertSame(
            0,
            PostModerationEvent::query()->where('post_id', $postId)->where('event', 'like', 'report_%')->count()
        );
    }

    public function test_admin_of_a_who_is_non_admin_member_of_b_cannot_resolve_b(): void
    {
        [$groupA] = $this->publishedCommunityPost();
        [$groupB, $authorB, , $postB] = $this->publishedCommunityPost();
        $reportB = $this->createOpenReport($postB, $authorB);
        $adminA = $this->municipalAdministratorFor($groupA->municipality);
        MunicipalityMember::factory()->create([
            'municipality_id' => $groupB->municipality_id,
            'user_id' => $adminA->id,
            'role' => MunicipalityMemberRole::Funcionario,
            'status' => MunicipalityMemberStatus::Active,
        ]);
        $before = PostModerationEvent::query()->count();

        try {
            $this->service()->execute($reportB, $adminA->fresh(), PostReportStatus::Resolved, 'Cruce');
            $this->fail('No debe resolver reportes del municipio B.');
        } catch (AuthorizationException) {
            // expected
        }

        $this->assertSame(PostReportStatus::Open, $reportB->fresh()->status);
        $this->assertSame($before, PostModerationEvent::query()->count());
    }

    public function test_reviewing_then_resolved_creates_two_distinct_events(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);

        $this->service()->execute($report, $admin, PostReportStatus::Reviewing);
        $this->service()->execute($report->fresh(), $admin, PostReportStatus::Resolved, 'Cierre posterior');

        $events = $this->eventsForReport($report)->sortBy('id')->values();
        $this->assertCount(2, $events);
        $this->assertSame(TransitionPostReportService::EVENT_REVIEWING, $events[0]->event);
        $this->assertSame(PostReportStatus::Open->value, $events[0]->from_status);
        $this->assertSame(PostReportStatus::Reviewing->value, $events[0]->to_status);
        $this->assertSame(TransitionPostReportService::EVENT_RESOLVED, $events[1]->event);
        $this->assertSame(PostReportStatus::Reviewing->value, $events[1]->from_status);
        $this->assertSame(PostReportStatus::Resolved->value, $events[1]->to_status);
    }

    public function test_transition_does_not_hide_the_post_or_create_hidden_events(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);

        $this->service()->execute($report, $admin, PostReportStatus::Resolved, 'Sin ocultar');

        $this->assertSame(PostStatus::Published, $post->fresh()->status);
        $this->assertSame(
            0,
            PostModerationEvent::query()->where('post_id', $post->id)->where('event', 'hidden')->count()
        );
        $this->assertCount(1, $this->eventsForReport($report));
    }

    private function service(): TransitionPostReportService
    {
        return app(TransitionPostReportService::class);
    }

    private function createOpenReport($post, User $reporter, array $overrides = []): PostReport
    {
        return PostReport::query()->create(array_merge([
            'post_id' => $post->id,
            'municipality_id' => $post->municipality_id,
            'reporter_id' => $reporter->id,
            'reason_code' => 'spam',
            'status' => PostReportStatus::Open,
        ], $overrides));
    }

    /**
     * @return Collection<int, PostModerationEvent>
     */
    private function eventsForReport(PostReport $report)
    {
        return PostModerationEvent::query()
            ->get()
            ->filter(fn (PostModerationEvent $event): bool => ($event->payload['report_id'] ?? null) === $report->id)
            ->values();
    }
}
