<?php

namespace Tests\Feature\Posts;

use App\Domains\Posts\Enums\PostRevisionStatus;
use App\Domains\Posts\Exceptions\PostDomainException;
use App\Domains\Posts\Models\PostAttachment;
use App\Domains\Posts\Models\PostRevision;
use App\Domains\Posts\Services\AttachPostFileService;
use App\Domains\Posts\Services\UpdatePostRevisionService;
use App\Domains\Posts\Services\SubmitPostService;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class PostAttachmentSecurityTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
        Storage::fake('posts_private');
    }

    public function test_foreign_group_member_cannot_download_attachment(): void
    {
        [$group, $author, $moderator, $post, , $attachment] = $this->publishedPostWithAttachment();
        $intruder = User::factory()->create();
        $otherGroup = \App\Domains\Neighborhoods\Models\NeighborhoodGroup::factory()->create();
        $this->addMemberToGroup($otherGroup, $intruder);

        Sanctum::actingAs($intruder);
        $this->getJson("/api/v1/posts/{$post->id}/attachments/{$attachment->id}")->assertNotFound();
    }

    public function test_pending_revision_attachment_hidden_from_feed_reader(): void
    {
        [$group, $author, $moderator, $post, , $publishedAttachment] = $this->publishedPostWithAttachment();
        $reader = User::factory()->create();
        $this->addMemberToGroup($group, $reader);

        app(UpdatePostRevisionService::class)->execute(
            $post,
            $author,
            $this->postCategory->id,
            'Enmienda',
            'Nuevo cuerpo',
        );
        $pending = PostRevision::query()->where('post_id', $post->id)->where('status', PostRevisionStatus::Draft)->first();
        $pendingAttachment = $this->storePdf($pending, $author);
        app(SubmitPostService::class)->execute($post->fresh(), $author);

        Sanctum::actingAs($reader);
        $this->getJson("/api/v1/posts/{$post->id}/attachments/{$pendingAttachment->id}")->assertNotFound();
        $this->getJson("/api/v1/posts/{$post->id}/attachments/{$publishedAttachment->id}")->assertOk();
    }

    public function test_author_and_moderator_can_download_pending_attachment(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        app(UpdatePostRevisionService::class)->execute($post, $author, $this->postCategory->id, 'Enmienda', 'Texto');
        $pending = PostRevision::query()->where('post_id', $post->id)->where('status', PostRevisionStatus::Draft)->first();
        app(SubmitPostService::class)->execute($post->fresh(), $author);
        $attachment = $this->storePdf($pending->fresh(), $author);

        Sanctum::actingAs($author);
        $this->getJson("/api/v1/posts/{$post->id}/attachments/{$attachment->id}")->assertOk();

        Sanctum::actingAs($moderator);
        $this->getJson("/api/v1/posts/{$post->id}/attachments/{$attachment->id}")->assertOk();
    }

    public function test_attachment_stored_on_private_disk(): void
    {
        [$group, $author, $moderator, $post, , $attachment] = $this->publishedPostWithAttachment();

        $this->assertSame(config('red_vecinal.posts.disk'), $attachment->disk);
        $this->assertStringNotContainsString('..', $attachment->path);
        Storage::disk($attachment->disk)->assertExists($attachment->path);
        $this->assertStringStartsWith((string) $post->municipality_id.'/', $attachment->path);
    }

    public function test_cannot_download_attachment_using_wrong_post_id(): void
    {
        [$groupA, $authorA, $modA, $postA, , $attachmentA] = $this->publishedPostWithAttachment();
        [$groupB, $authorB, $modB, $postB] = $this->publishedCommunityPost();

        Sanctum::actingAs($authorB);
        $this->getJson("/api/v1/posts/{$postB->id}/attachments/{$attachmentA->id}")->assertNotFound();
    }

    public function test_rejects_disallowed_mime_type(): void
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $post = app(\App\Domains\Posts\Services\CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->postCategory->id,
            'T',
            'C',
        );
        $revision = $post->revisions()->first();
        $file = UploadedFile::fake()->create('evil.php', 10, 'application/x-php');

        $this->expectException(PostDomainException::class);
        app(AttachPostFileService::class)->execute($revision, $author, $file);
    }

    public function test_enforces_max_attachments_per_revision(): void
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $post = app(\App\Domains\Posts\Services\CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->postCategory->id,
            'T',
            'C',
        );
        $revision = $post->revisions()->first();

        for ($i = 0; $i < 5; $i++) {
            $this->storePdf($revision, $author);
        }

        $this->expectException(PostDomainException::class);
        $this->storePdf($revision, $author);
    }

    public function test_enforces_max_file_size(): void
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $post = app(\App\Domains\Posts\Services\CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->postCategory->id,
            'T',
            'C',
        );
        $revision = $post->revisions()->first();
        $maxKb = (int) config('red_vecinal.posts.max_attachment_size_kb', 5120);
        $file = UploadedFile::fake()->create('big.pdf', $maxKb + 100, 'application/pdf');

        $this->expectException(PostDomainException::class);
        app(AttachPostFileService::class)->execute($revision, $author, $file);
    }

    private function storePdf(PostRevision $revision, User $user): PostAttachment
    {
        $file = UploadedFile::fake()->createWithContent('doc.pdf', "%PDF-1.4\n%%EOF");

        return app(AttachPostFileService::class)->execute($revision, $user, $file);
    }

    private function publishedPostWithAttachment(): array
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $post = app(\App\Domains\Posts\Services\CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->postCategory->id,
            'Con adjunto',
            'Cuerpo',
        );
        $revision = $post->revisions()->first();
        $attachment = $this->storePdf($revision, $author);
        app(SubmitPostService::class)->execute($post, $author);
        app(\App\Domains\Posts\Services\ApprovePostService::class)->execute($post->fresh(), $moderator);
        $post = $post->fresh(['currentPublishedRevision', 'neighborhoodGroup']);

        return [$group, $author, $moderator, $post, $revision->fresh(), $attachment->fresh()];
    }
}
