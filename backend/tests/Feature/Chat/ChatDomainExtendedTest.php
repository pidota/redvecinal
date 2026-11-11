<?php

namespace Tests\Feature\Chat;

use App\Domains\Chat\Enums\ChatMessageReportStatus;
use App\Domains\Chat\Enums\ChatMessageStatus;
use App\Domains\Chat\Exceptions\ChatDomainException;
use App\Domains\Chat\Services\DeleteChatMessageService;
use App\Domains\Chat\Services\EditChatMessageService;
use App\Domains\Chat\Services\MarkChatRoomReadService;
use App\Domains\Chat\Services\ReportChatMessageService;
use App\Domains\Chat\Services\ResolveChatMessageReportService;
use App\Domains\Chat\Services\SendChatMessageService;
use App\Domains\Chat\Services\ViewReportedChatMessageService;
use App\Domains\Chat\Support\ChatMessageEventRecorder;
use App\Domains\Municipality\Models\Municipality as MunicipalityModel;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Event;
use Laravel\Sanctum\Sanctum;
use Mockery;
use Tests\Concerns\CreatesChatFixtures;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class ChatDomainExtendedTest extends TestCase
{
    use CreatesChatFixtures, CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_author_can_edit_within_window(): void
    {
        Carbon::setTestNow('2026-01-01 12:00:00');

        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);
        $message = app(SendChatMessageService::class)->execute($room, $author, 'Original');

        $edited = app(EditChatMessageService::class)->execute($message, $author, 'Editado');

        $this->assertSame('Editado', $edited->body);
        $this->assertSame(2, $edited->version);
    }

    public function test_edit_outside_window_is_rejected(): void
    {
        Carbon::setTestNow('2026-01-01 12:00:00');

        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);
        $message = app(SendChatMessageService::class)->execute($room, $author, 'Original');

        Carbon::setTestNow('2026-01-01 13:00:00');

        $this->expectException(ChatDomainException::class);
        app(EditChatMessageService::class)->execute($message->fresh(), $author, 'Tarde');
    }

    public function test_cannot_edit_foreign_message(): void
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);
        $message = app(SendChatMessageService::class)->execute($room, $author, 'De autor');

        $this->expectException(\Illuminate\Auth\Access\AuthorizationException::class);
        app(EditChatMessageService::class)->execute($message, $moderator, 'Hack');
    }

    public function test_logical_delete_by_author(): void
    {
        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);
        $message = app(SendChatMessageService::class)->execute($room, $author, 'Borrar');

        $deleted = app(DeleteChatMessageService::class)->execute($message, $author);

        $this->assertSame(ChatMessageStatus::DeletedBySender, $deleted->status);
        $this->assertNotNull($deleted->deleted_at);
    }

    public function test_member_can_report_visible_message(): void
    {
        [$group, $author, $reporter] = $this->twoMembersInGroup();
        $room = $this->chatRoomForGroup($group);
        $message = app(SendChatMessageService::class)->execute($room, $author, 'Reportable');

        $report = app(ReportChatMessageService::class)->execute($message, $reporter, 'spam', 'Detalle');

        $this->assertDatabaseHas('chat_message_reports', [
            'id' => $report->id,
            'chat_message_id' => $message->id,
            'reporter_id' => $reporter->id,
        ]);
    }

    public function test_municipal_admin_can_view_reported_message_with_audit(): void
    {
        [$group, $author, $reporter] = $this->twoMembersInGroup();
        $room = $this->chatRoomForGroup($group);
        $message = app(SendChatMessageService::class)->execute($room, $author, 'Sensible');
        $report = app(ReportChatMessageService::class)->execute($message, $reporter, 'abuso', null);

        $admin = $this->municipalAdministratorFor($group->municipality);
        $admin->givePermissionTo('chat.reports.view');

        $viewed = app(ViewReportedChatMessageService::class)->execute($report, $admin);

        $this->assertSame('Sensible', $viewed->body);
        $this->assertDatabaseHas('chat_message_events', [
            'chat_message_id' => $message->id,
            'event' => 'supervisor_viewed',
        ]);
    }

    public function test_foreign_municipal_admin_cannot_view_reported_message(): void
    {
        [$group, $author, $reporter] = $this->twoMembersInGroup();
        $message = app(SendChatMessageService::class)->execute(
            $this->chatRoomForGroup($group),
            $author,
            'Otro municipio',
        );
        $report = app(ReportChatMessageService::class)->execute($message, $reporter, 'spam', null);

        $otherMunicipality = MunicipalityModel::factory()->create();
        $foreignAdmin = $this->municipalAdministratorFor($otherMunicipality);
        $foreignAdmin->givePermissionTo('chat.reports.view');

        $this->expectException(\Illuminate\Auth\Access\AuthorizationException::class);
        app(ViewReportedChatMessageService::class)->execute($report, $foreignAdmin);
    }

    public function test_municipal_admin_can_resolve_report(): void
    {
        [$group, $author, $reporter] = $this->twoMembersInGroup();
        $message = app(SendChatMessageService::class)->execute(
            $this->chatRoomForGroup($group),
            $author,
            'Resolver',
        );
        $report = app(ReportChatMessageService::class)->execute($message, $reporter, 'spam', null);

        $admin = $this->municipalAdministratorFor($group->municipality);
        $admin->givePermissionTo('chat.reports.resolve');

        $resolved = app(ResolveChatMessageReportService::class)->execute(
            $report,
            $admin,
            ChatMessageReportStatus::Resolved,
            'Revisado',
        );

        $this->assertSame(ChatMessageReportStatus::Resolved, $resolved->status);
    }

    public function test_concurrent_read_markers_keep_highest(): void
    {
        [$group, $reader, $other] = $this->twoMembersInGroup();
        $room = $this->chatRoomForGroup($group);
        $send = app(SendChatMessageService::class);
        $m1 = $send->execute($room, $other, '1');
        $m2 = $send->execute($room, $other, '2');
        $mark = app(MarkChatRoomReadService::class);

        DB::transaction(fn () => $mark->execute($room, $reader, $m1->id));
        $state = $mark->execute($room, $reader, $m2->id);

        $this->assertSame($m2->id, $state->last_read_message_id);
    }

    public function test_send_rolls_back_when_audit_recorder_fails(): void
    {
        Event::fake();

        $recorder = Mockery::mock(ChatMessageEventRecorder::class);
        $recorder->shouldReceive('record')->andThrow(new \RuntimeException('audit fail'));
        $this->app->instance(ChatMessageEventRecorder::class, $recorder);

        [$group, $author] = $this->activeGroupTriple();
        $room = $this->chatRoomForGroup($group);

        try {
            app(SendChatMessageService::class)->execute($room, $author, 'No persiste');
        } catch (\RuntimeException) {
            //
        }

        $this->assertDatabaseCount('chat_messages', 0);
    }

    public function test_api_municipality_isolation_on_message_show(): void
    {
        [$groupA, $authorA] = $this->activeGroupTriple();
        [$groupB, $authorB] = $this->activeGroupTriple();
        $roomA = $this->chatRoomForGroup($groupA);
        $message = app(SendChatMessageService::class)->execute($roomA, $authorA, 'Privado');

        Sanctum::actingAs($authorB);
        $this->getJson("/api/v1/chat/messages/{$message->id}")->assertForbidden();
    }

    private function twoMembersInGroup(): array
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $memberB = \App\Models\User::factory()->create();
        $this->addMemberToGroup($group, $memberB);

        return [$group, $author, $memberB];
    }
}
