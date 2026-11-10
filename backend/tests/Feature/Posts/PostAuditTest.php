<?php

namespace Tests\Feature\Posts;

use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Models\PostModerationEvent;
use App\Domains\Posts\Services\ArchivePostService;
use App\Domains\Posts\Services\HidePostService;
use App\Domains\Posts\Services\RestorePostService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class PostAuditTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_moderation_events_recorded_for_lifecycle(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();

        app(HidePostService::class)->execute($post, $moderator, 'Revisión');
        app(RestorePostService::class)->execute($post->fresh(), $moderator);
        app(ArchivePostService::class)->execute($post->fresh(), $moderator);

        $events = PostModerationEvent::query()->where('post_id', $post->id)->pluck('event')->all();

        $this->assertContains('created', $events);
        $this->assertContains('submitted', $events);
        $this->assertContains('approved', $events);
        $this->assertContains('hidden', $events);
        $this->assertContains('restored', $events);
        $this->assertContains('archived', $events);
    }

    public function test_audit_events_store_status_transitions(): void
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $post = app(\App\Domains\Posts\Services\CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->postCategory->id,
            'Audit',
            'Body',
        );
        app(\App\Domains\Posts\Services\SubmitPostService::class)->execute($post, $author);
        app(\App\Domains\Posts\Services\ApprovePostService::class)->execute($post->fresh(), $moderator);

        $approved = PostModerationEvent::query()
            ->where('post_id', $post->id)
            ->where('event', 'approved')
            ->first();

        $this->assertNotNull($approved);
        $this->assertSame(PostStatus::Pending->value, $approved->from_status);
        $this->assertSame(PostStatus::Published->value, $approved->to_status);
    }
}
