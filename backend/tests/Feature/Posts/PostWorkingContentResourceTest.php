<?php

namespace Tests\Feature\Posts;

use App\Domains\Posts\Enums\PostRevisionStatus;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostRevision;
use App\Domains\Posts\Services\CreateCommunityPostService;
use App\Domains\Posts\Services\RejectPostService;
use App\Domains\Posts\Services\SubmitPostService;
use App\Domains\Posts\Services\UpdatePostRevisionService;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class PostWorkingContentResourceTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_author_receives_working_content_on_empty_draft_after_create(): void
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        Sanctum::actingAs($author);

        $response = $this->postJson('/api/v1/posts', [
            'neighborhood_group_id' => $group->id,
            'category_id' => $this->postCategory->id,
            'title' => 'Borrador nuevo',
            'body' => 'Sin adjuntos aún',
        ])->assertOk();

        $data = $response->json('data');
        $this->assertIsArray($data['working_content']);
        $this->assertSame('Borrador nuevo', $data['working_content']['title']);
        $this->assertNull($data['content']);

        $revision = PostRevision::query()->where('post_id', $data['id'])->firstOrFail();
        $this->assertSame($revision->id, $data['working_content']['revision_id']);
        $this->assertSame($revision->post_id, $data['id']);
    }

    public function test_author_receives_working_content_on_rejected_post(): void
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $post = app(CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->postCategory->id,
            'Para rechazar',
            'Cuerpo',
        );
        app(SubmitPostService::class)->execute($post, $author);
        app(RejectPostService::class)->execute($post->fresh(), $moderator, 'No cumple');

        Sanctum::actingAs($author);
        $response = $this->getJson('/api/v1/posts/'.$post->fresh()->id)->assertOk();
        $data = $response->json('data');

        $this->assertSame('rejected', $data['status']);
        $working = $data['working_content'];
        $this->assertNotNull($working);
        $revision = PostRevision::query()
            ->where('post_id', $post->id)
            ->whereIn('status', [PostRevisionStatus::Rejected, PostRevisionStatus::Draft])
            ->latest('revision_number')
            ->firstOrFail();
        $this->assertSame($revision->id, $working['revision_id']);
    }

    public function test_pending_post_does_not_expose_working_content(): void
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $post = app(CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->postCategory->id,
            'En revisión',
            'Texto',
        );
        app(SubmitPostService::class)->execute($post, $author);

        Sanctum::actingAs($author);
        $response = $this->getJson('/api/v1/posts/'.$post->fresh()->id)->assertOk();
        $this->assertNull($response->json('data.working_content'));
    }

    public function test_published_without_amendment_has_null_working_content(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();

        Sanctum::actingAs($author);
        $response = $this->getJson('/api/v1/posts/'.$post->id)->assertOk();
        $data = $response->json('data');

        $this->assertNotNull($data['content']['revision_id']);
        $this->assertNull($data['working_content']);
        $this->assertNotSame($data['content']['revision_id'], $data['working_content']['revision_id'] ?? null);
    }

    public function test_published_with_draft_amendment_exposes_amendment_as_working_content(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();

        app(UpdatePostRevisionService::class)->execute(
            $post,
            $author,
            $this->postCategory->id,
            'Enmienda borrador',
            'Nuevo texto',
        );

        $draft = PostRevision::query()
            ->where('post_id', $post->id)
            ->where('status', PostRevisionStatus::Draft)
            ->latest('revision_number')
            ->firstOrFail();

        Sanctum::actingAs($author);
        $response = $this->getJson('/api/v1/posts/'.$post->fresh()->id)->assertOk();
        $working = $response->json('data.working_content');

        $this->assertNotNull($working);
        $this->assertSame($draft->id, $working['revision_id']);
        $this->assertSame('Enmienda borrador', $working['title']);
        $this->assertNotSame($post->current_published_revision_id, $draft->id);
    }

    public function test_foreign_member_cannot_view_draft_and_working_content_stays_unexposed(): void
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $post = app(CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->postCategory->id,
            'Privado',
            'Secreto',
        );

        $intruder = User::factory()->create();
        $this->addMemberToGroup($group, $intruder);

        Sanctum::actingAs($intruder);
        $this->getJson('/api/v1/posts/'.$post->id)->assertNotFound();
    }

    public function test_unauthenticated_request_has_no_working_content_on_public_post(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();

        $response = $this->getJson('/api/v1/posts/'.$post->id)->assertUnauthorized();
        $this->assertNotSame(200, $response->status());
    }

    public function test_mine_list_includes_working_content_for_author_draft(): void
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $post = app(CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->postCategory->id,
            'Mi borrador',
            'Lista',
        );

        Sanctum::actingAs($author);
        $item = collect($this->getJson('/api/v1/me/posts')->json('data'))->firstWhere('id', $post->id);
        $this->assertNotNull($item);
        $this->assertNotNull($item['working_content']['revision_id']);
    }
}