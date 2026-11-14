<?php

namespace Tests\Feature\Posts;

use App\Domains\Posts\Models\PostAttachment;
use App\Domains\Posts\Models\PostRevision;
use App\Domains\Posts\Services\CreateCommunityPostService;
use App\Domains\Posts\Services\SubmitPostService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class PostAttachmentHttpFlowTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
        Storage::fake(config('red_vecinal.posts.disk', 'posts_private'));
    }

    public function test_http_create_upload_submit_and_block_upload_after_pending(): void
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        Sanctum::actingAs($author);

        $create = $this->postJson('/api/v1/posts', [
            'neighborhood_group_id' => $group->id,
            'category_id' => $this->postCategory->id,
            'title' => 'Con adjunto',
            'body' => 'Flujo HTTP',
        ])->assertOk();

        $postId = (int) $create->json('data.id');
        $revisionId = (int) $create->json('data.working_content.revision_id');
        $revision = PostRevision::query()->findOrFail($revisionId);
        $this->assertSame($postId, $revision->post_id);

        $file = UploadedFile::fake()->createWithContent('informe.pdf', "%PDF-1.4\n%%EOF");

        $upload = $this->post("/api/v1/posts/{$postId}/attachments", [
            'revision_id' => $revisionId,
            'file' => $file,
        ])->assertCreated();

        $attachmentId = (int) $upload->json('id');
        $this->assertSame($revisionId, $upload->json('revision_id'));
        $attachment = PostAttachment::query()->findOrFail($attachmentId);
        $this->assertSame($revisionId, $attachment->post_revision_id);
        $this->assertSame($postId, $attachment->post_id);

        $this->postJson("/api/v1/posts/{$postId}/submit")->assertOk();
        $this->assertSame('pending', $this->getJson("/api/v1/posts/{$postId}")->json('data.status'));
        $this->assertNull($this->getJson("/api/v1/posts/{$postId}")->json('data.working_content'));

        $secondFile = UploadedFile::fake()->createWithContent('otro.pdf', "%PDF-1.4\n%%EOF");
        $this->post("/api/v1/posts/{$postId}/attachments", [
            'revision_id' => $revisionId,
            'file' => $secondFile,
        ])->assertForbidden();
    }

    public function test_attachment_rejects_revision_from_another_post(): void
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        Sanctum::actingAs($author);

        $postA = app(CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->postCategory->id,
            'A',
            'Cuerpo A',
        );
        $postB = app(CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->postCategory->id,
            'B',
            'Cuerpo B',
        );

        $revisionA = $postA->revisions()->firstOrFail();
        $file = UploadedFile::fake()->createWithContent('x.pdf', "%PDF-1.4\n%%EOF");

        $this->post("/api/v1/posts/{$postB->id}/attachments", [
            'revision_id' => $revisionA->id,
            'file' => $file,
        ])->assertNotFound();
    }
}