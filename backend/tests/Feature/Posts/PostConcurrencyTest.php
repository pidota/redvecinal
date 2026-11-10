<?php

namespace Tests\Feature\Posts;

use App\Domains\Posts\Enums\PostRevisionStatus;
use App\Domains\Posts\Exceptions\PostDomainException;
use App\Domains\Posts\Models\PostRevision;
use App\Domains\Posts\Services\ApprovePostService;
use App\Domains\Posts\Services\CreateCommunityPostService;
use App\Domains\Posts\Services\RejectPostService;
use App\Domains\Posts\Services\SubmitPostService;
use App\Domains\Posts\Services\UpdatePostRevisionService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class PostConcurrencyTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_cannot_open_second_amendment_while_one_exists(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();

        app(UpdatePostRevisionService::class)->execute($post, $author, $this->postCategory->id, 'A', 'Uno');

        $this->expectException(PostDomainException::class);
        app(UpdatePostRevisionService::class)->execute($post->fresh(), $author, $this->postCategory->id, 'B', 'Dos');
    }

    public function test_approve_and_reject_race_leaves_single_outcome(): void
    {
        [$group, $author, $modA, $modB] = $this->groupWithTwoModerators();
        $post = app(CreateCommunityPostService::class)->execute($group, $author, $this->postCategory->id, 'T', 'C');
        app(SubmitPostService::class)->execute($post, $author);

        app(ApprovePostService::class)->execute($post->fresh(), $modA);

        $this->expectException(PostDomainException::class);
        app(RejectPostService::class)->execute($post->fresh(), $modB, 'Tarde');
    }

    public function test_rejected_amendment_keeps_published_snapshot(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        $publishedId = $post->current_published_revision_id;
        $originalTitle = $post->currentPublishedRevision->title;

        app(UpdatePostRevisionService::class)->execute($post, $author, $this->postCategory->id, 'Enmienda', 'Nuevo');
        app(SubmitPostService::class)->execute($post->fresh(), $author);
        app(RejectPostService::class)->execute($post->fresh(), $moderator, 'No procede');

        $post->refresh();
        $this->assertSame($publishedId, $post->current_published_revision_id);
        $this->assertSame($originalTitle, $post->currentPublishedRevision->title);
        $this->assertFalse($post->pendingRevision()->exists());
    }

    public function test_pending_amendment_can_receive_attachments(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        app(UpdatePostRevisionService::class)->execute($post, $author, $this->postCategory->id, 'Con adjunto', 'Texto');
        $draft = PostRevision::query()->where('post_id', $post->id)->where('status', PostRevisionStatus::Draft)->latest('id')->first();
        app(SubmitPostService::class)->execute($post->fresh(), $author);
        $pending = $draft->fresh();

        $file = \Illuminate\Http\UploadedFile::fake()->createWithContent('a.pdf', "%PDF-1.4\n%%EOF");
        \Illuminate\Support\Facades\Storage::fake(config('red_vecinal.posts.disk', 'posts_private'));
        $attachment = app(\App\Domains\Posts\Services\AttachPostFileService::class)->execute($pending, $author, $file);

        $this->assertSame($pending->id, $attachment->post_revision_id);
    }

    private function groupWithTwoModerators(): array
    {
        $group = \App\Domains\Neighborhoods\Models\NeighborhoodGroup::factory()->create();
        $author = \App\Models\User::factory()->create();
        $modA = \App\Models\User::factory()->create();
        $modB = \App\Models\User::factory()->create();

        $this->addMemberToGroup($group, $author);
        $this->addMemberToGroup($group, $modA, \App\Domains\Neighborhoods\Enums\MembershipRole::Moderator);
        $this->addMemberToGroup($group, $modB, \App\Domains\Neighborhoods\Enums\MembershipRole::Moderator);

        return [$group, $author, $modA, $modB];
    }
}
