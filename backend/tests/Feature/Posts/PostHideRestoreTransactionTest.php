<?php

namespace Tests\Feature\Posts;

use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Models\PostModerationEvent;
use App\Domains\Posts\Services\HidePostService;
use App\Domains\Posts\Services\RestorePostService;
use App\Domains\Posts\Support\PostModerationEventRecorder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use RuntimeException;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class PostHideRestoreTransactionTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_hide_rolls_back_status_when_audit_recorder_fails(): void
    {
        [$group, , $moderator, $post] = $this->publishedCommunityPost();

        $this->mock(PostModerationEventRecorder::class, function ($mock): void {
            $mock->shouldReceive('record')->andThrow(new RuntimeException('fallo de auditoría'));
        });

        try {
            app(HidePostService::class)->execute($post, $moderator, 'Prueba');
            $this->fail('Se esperaba excepción del recorder.');
        } catch (RuntimeException) {
            // expected
        }

        $this->assertSame(PostStatus::Published, $post->fresh()->status);
        $this->assertDatabaseMissing('post_moderation_events', [
            'post_id' => $post->id,
            'event' => 'hidden',
        ]);
    }

    public function test_restore_rolls_back_status_when_audit_recorder_fails(): void
    {
        [$group, , $moderator, $post] = $this->publishedCommunityPost();
        app(HidePostService::class)->execute($post, $moderator, 'Ocultar');
        $hidden = $post->fresh();
        $this->assertSame(PostStatus::Hidden, $hidden->status);

        $this->mock(PostModerationEventRecorder::class, function ($mock): void {
            $mock->shouldReceive('record')->andThrow(new RuntimeException('fallo de auditoría'));
        });

        try {
            app(RestorePostService::class)->execute($hidden, $moderator);
            $this->fail('Se esperaba excepción del recorder.');
        } catch (RuntimeException) {
            // expected
        }

        $this->assertSame(PostStatus::Hidden, $hidden->fresh()->status);
        $this->assertSame(
            0,
            PostModerationEvent::query()->where('post_id', $post->id)->where('event', 'restored')->count()
        );
    }
}
