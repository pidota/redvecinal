<?php

namespace Tests\Feature\Posts;

use App\Domains\Municipality\Models\Municipality;
use App\Domains\Posts\Enums\PostCommentStatus;
use App\Domains\Posts\Enums\PostRevisionStatus;
use App\Domains\Posts\Models\PostCategory;
use App\Domains\Posts\Models\PostRevision;
use App\Domains\Posts\Models\PostComment;
use App\Domains\Posts\Services\ApprovePostService;
use App\Domains\Posts\Services\AttachPostFileService;
use App\Domains\Posts\Services\CreateCommunityPostService;
use App\Domains\Posts\Services\PublishOfficialPostService;
use App\Domains\Posts\Services\SubmitPostService;
use App\Domains\Posts\Services\UpdatePostRevisionService;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class PostResourceEnrichmentTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_feed_includes_additive_json_shape_without_author_pii(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        Sanctum::actingAs($author);

        $response = $this->getJson('/api/v1/posts')->assertOk();
        $item = collect($response->json('data'))->firstWhere('id', $post->id);

        $this->assertNotNull($item);
        $this->assertSame('community', $item['post_kind']);
        $this->assertSame($author->id, $item['author']['id']);
        $this->assertSame($author->name, $item['author']['name']);
        $this->assertArrayNotHasKey('email', $item['author']);
        $this->assertSame($group->id, $item['neighborhood_group']['id']);
        $this->assertSame($this->postCategory->slug, $item['category']['slug']);
        $this->assertSame($group->municipality_id, $item['municipality']['id']);
        $this->assertArrayHasKey('engagement', $item);
        $this->assertArrayHasKey('attachments', $item);
        $this->assertArrayHasKey('pending_attachments', $item);
        $this->assertArrayHasKey('meta', $response->json());
        $this->assertArrayHasKey('links', $response->json());
    }

    public function test_municipal_post_has_null_group_and_municipal_kind(): void
    {
        $municipality = Municipality::factory()->create();
        $admin = $this->municipalAdministratorFor($municipality);
        $category = PostCategory::query()->where('slug', 'comunicado-municipal')->firstOrFail();

        $post = app(PublishOfficialPostService::class)->execute(
            $municipality,
            $admin,
            $category->id,
            'Comunicado',
            'Texto oficial',
        );

        $member = User::factory()->create();
        $group = \App\Domains\Neighborhoods\Models\NeighborhoodGroup::factory()->create([
            'municipality_id' => $municipality->id,
        ]);
        $this->addMemberToGroup($group, $member);

        Sanctum::actingAs($member);
        $response = $this->getJson('/api/v1/posts/'.$post->id)->assertOk();

        $this->assertSame('municipal', $response->json('data.post_kind'));
        $this->assertNull($response->json('data.neighborhood_group'));
        $this->assertSame('comunicado-municipal', $response->json('data.category.slug'));
    }

    public function test_engagement_counts_and_my_reaction(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        $reader = User::factory()->create();
        $this->addMemberToGroup($group, $reader);

        PostComment::query()->create([
            'post_id' => $post->id,
            'municipality_id' => $post->municipality_id,
            'author_id' => $author->id,
            'body' => 'Visible',
            'status' => PostCommentStatus::Visible,
        ]);
        PostComment::query()->create([
            'post_id' => $post->id,
            'municipality_id' => $post->municipality_id,
            'author_id' => $author->id,
            'body' => 'Oculto',
            'status' => PostCommentStatus::Hidden,
        ]);

        Sanctum::actingAs($reader);
        $this->putJson('/api/v1/posts/'.$post->id.'/reactions', ['type' => 'celebrate'])->assertOk();

        $response = $this->getJson('/api/v1/posts/'.$post->id)->assertOk();
        $engagement = $response->json('data.engagement');

        $this->assertSame(1, $engagement['comments_count']);
        $this->assertSame(1, $engagement['reactions_count']);
        $this->assertSame('celebrate', $engagement['my_reaction']['type']);
    }

    public function test_published_attachments_exposed_with_download_url_not_storage_path(): void
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $post = app(CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->postCategory->id,
            'Con adjunto',
            'Cuerpo',
        );
        $revision = $post->revisions()->first();
        $file = UploadedFile::fake()->createWithContent('informe.pdf', "%PDF-1.4\n%%EOF");
        $attachment = app(AttachPostFileService::class)->execute($revision, $author, $file);
        app(SubmitPostService::class)->execute($post, $author);
        app(ApprovePostService::class)->execute($post->fresh(), $moderator);
        $post = $post->fresh(['currentPublishedRevision']);

        Sanctum::actingAs($author);
        $response = $this->getJson('/api/v1/posts/'.$post->id)->assertOk();
        $attachments = $response->json('data.attachments');

        $this->assertCount(1, $attachments);
        $this->assertSame($attachment->id, $attachments[0]['id']);
        $this->assertSame(
            '/api/v1/posts/'.$post->id.'/attachments/'.$attachment->id,
            $attachments[0]['download_url'],
        );
        $this->assertStringNotContainsString('http', strtolower($attachments[0]['download_url']));
        $this->assertStringNotContainsString($attachment->path, $attachments[0]['download_url']);
        $this->assertArrayNotHasKey('path', $attachments[0]);
        $this->assertArrayNotHasKey('disk', $attachments[0]);
        $this->assertArrayNotHasKey('checksum', $attachments[0]);
    }

    public function test_pending_attachments_hidden_from_unauthorized_reader(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        $reader = User::factory()->create();
        $this->addMemberToGroup($group, $reader);

        app(UpdatePostRevisionService::class)->execute(
            $post,
            $author,
            $this->postCategory->id,
            'Nuevo título',
            'Nuevo cuerpo',
        );
        $draftRevision = PostRevision::query()
            ->where('post_id', $post->id)
            ->where('status', PostRevisionStatus::Draft)
            ->firstOrFail();

        $file = UploadedFile::fake()->createWithContent('borrador.pdf', "%PDF-1.4\n%%EOF");
        $pendingAttachment = app(AttachPostFileService::class)->execute($draftRevision, $author, $file);
        app(SubmitPostService::class)->execute($post->fresh(), $author);

        Sanctum::actingAs($reader);
        $response = $this->getJson('/api/v1/posts/'.$post->id)->assertOk();

        $this->assertNotNull($response->json('data.content'));
        $this->assertNull($response->json('data.pending_content'));
        $this->assertSame([], $response->json('data.pending_attachments'));
        $attachmentIds = collect($response->json('data.attachments'))->pluck('id');
        $this->assertFalse($attachmentIds->contains($pendingAttachment->id));
    }

    public function test_feed_exposes_only_published_revision_attachments_not_pending_amendment(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        $publishedAttachmentId = null;
        $post = $post->fresh(['currentPublishedRevision']);
        $publishedAttachmentId = optional($post->currentPublishedRevision?->attachments->first())->id;

        app(UpdatePostRevisionService::class)->execute(
            $post,
            $author,
            $this->postCategory->id,
            'Enmienda',
            'Texto',
        );
        $draftRevision = PostRevision::query()
            ->where('post_id', $post->id)
            ->where('status', PostRevisionStatus::Draft)
            ->firstOrFail();
        $pendingFile = UploadedFile::fake()->createWithContent('solo-pending.pdf', "%PDF-1.4\n%%EOF");
        $pendingAttachment = app(AttachPostFileService::class)->execute($draftRevision, $author, $pendingFile);
        app(SubmitPostService::class)->execute($post->fresh(), $author);

        Sanctum::actingAs($author);
        $feedItem = collect($this->getJson('/api/v1/posts')->json('data'))->firstWhere('id', $post->id);
        $this->assertNotNull($feedItem);
        $feedAttachmentIds = collect($feedItem['attachments'])->pluck('id');
        $this->assertNotContains($pendingAttachment->id, $feedAttachmentIds);
        if ($publishedAttachmentId !== null) {
            $this->assertContains($publishedAttachmentId, $feedAttachmentIds->all());
        }
    }

    public function test_pending_attachments_visible_to_author(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();

        app(UpdatePostRevisionService::class)->execute(
            $post,
            $author,
            $this->postCategory->id,
            'Nuevo título',
            'Nuevo cuerpo',
        );
        $draftRevision = PostRevision::query()
            ->where('post_id', $post->id)
            ->where('status', PostRevisionStatus::Draft)
            ->firstOrFail();

        $file = UploadedFile::fake()->createWithContent('borrador.pdf', "%PDF-1.4\n%%EOF");
        $attachment = app(AttachPostFileService::class)->execute($draftRevision, $author, $file);
        app(SubmitPostService::class)->execute($post->fresh(), $author);

        Sanctum::actingAs($author);
        $response = $this->getJson('/api/v1/posts/'.$post->id)->assertOk();

        $pending = $response->json('data.pending_attachments');
        $this->assertCount(1, $pending);
        $this->assertSame($attachment->id, $pending[0]['id']);
    }

    public function test_foreign_group_post_not_in_feed_and_show_returns_404(): void
    {
        [$groupA, $authorA, $moderatorA, $postA] = $this->publishedCommunityPost();
        [$groupB, $authorB] = $this->activeGroupTriple();

        Sanctum::actingAs($authorB);
        $ids = collect($this->getJson('/api/v1/posts')->json('data'))->pluck('id');
        $this->assertFalse($ids->contains($postA->id));
        $this->getJson('/api/v1/posts/'.$postA->id)->assertNotFound();
    }

    public function test_posts_index_query_count_stays_bounded_for_multiple_items(): void
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        Sanctum::actingAs($author);

        foreach (range(1, 5) as $i) {
            $post = app(CreateCommunityPostService::class)->execute(
                $group,
                $author,
                $this->postCategory->id,
                'Título '.$i,
                'Cuerpo '.$i,
            );
            app(SubmitPostService::class)->execute($post, $author);
            app(ApprovePostService::class)->execute($post->fresh(), $moderator);
        }

        $queriesForMany = $this->countQueries(fn () => $this->getJson('/api/v1/posts')->assertOk());

        $this->assertLessThan(25, $queriesForMany);
    }

    /**
     * @param  callable(): mixed  $callback
     */
    private function countQueries(callable $callback): int
    {
        $count = 0;
        DB::listen(static function () use (&$count): void {
            $count++;
        });

        $callback();

        return $count;
    }
}