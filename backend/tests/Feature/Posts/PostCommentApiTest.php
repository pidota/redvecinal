<?php

namespace Tests\Feature\Posts;

use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Posts\Enums\PostCommentStatus;
use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Exceptions\PostDomainException;
use App\Domains\Posts\Models\PostComment;
use App\Domains\Posts\Services\HidePostService;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class PostCommentApiTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_index_returns_paginated_comments_with_author(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        $reader = User::factory()->create();
        $this->addMemberToGroup($group, $reader);

        PostComment::query()->create([
            'post_id' => $post->id,
            'municipality_id' => $post->municipality_id,
            'author_id' => $author->id,
            'body' => 'Primero',
            'status' => PostCommentStatus::Visible,
            'created_at' => now()->subMinutes(2),
        ]);
        PostComment::query()->create([
            'post_id' => $post->id,
            'municipality_id' => $post->municipality_id,
            'author_id' => $moderator->id,
            'body' => 'Segundo',
            'status' => PostCommentStatus::Visible,
            'created_at' => now()->subMinute(),
        ]);
        PostComment::query()->create([
            'post_id' => $post->id,
            'municipality_id' => $post->municipality_id,
            'author_id' => $author->id,
            'body' => 'Oculto',
            'status' => PostCommentStatus::Hidden,
        ]);

        Sanctum::actingAs($reader);
        $response = $this->getJson("/api/v1/posts/{$post->id}/comments")->assertOk();

        $response->assertJsonStructure([
            'data' => [
                '*' => [
                    'id',
                    'post_id',
                    'author_id',
                    'author' => ['id', 'name'],
                    'body',
                    'status',
                    'created_at',
                    'updated_at',
                ],
            ],
            'links',
            'meta',
        ]);

        $bodies = collect($response->json('data'))->pluck('body')->all();
        $this->assertSame(['Primero', 'Segundo'], $bodies);
        $this->assertStringNotContainsString('@', json_encode($response->json('data'), JSON_THROW_ON_ERROR));
    }

    public function test_store_returns_201_with_author_resource(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        Sanctum::actingAs($moderator);

        $response = $this->postJson("/api/v1/posts/{$post->id}/comments", [
            'body' => 'Comentario nuevo',
        ])->assertCreated();

        $response->assertJsonPath('data.body', 'Comentario nuevo');
        $response->assertJsonPath('data.author.id', $moderator->id);
        $response->assertJsonPath('data.author.name', $moderator->name);
        $response->assertJsonPath('data.status', PostCommentStatus::Visible->value);
        $response->assertJsonMissing(['email']);
    }

    public function test_store_validates_body_required_and_max_length(): void
    {
        [, , $moderator, $post] = $this->publishedCommunityPost();
        Sanctum::actingAs($moderator);

        $this->postJson("/api/v1/posts/{$post->id}/comments", [])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['body']);

        $this->postJson("/api/v1/posts/{$post->id}/comments", [
            'body' => str_repeat('a', 5001),
        ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['body']);
    }

    public function test_comments_require_authentication(): void
    {
        [, , , $post] = $this->publishedCommunityPost();

        $this->getJson("/api/v1/posts/{$post->id}/comments")->assertUnauthorized();
        $this->postJson("/api/v1/posts/{$post->id}/comments", ['body' => 'Hola'])
            ->assertUnauthorized();
    }

    public function test_comments_on_foreign_post_return_404(): void
    {
        [, , , $postA] = $this->publishedCommunityPost();
        [$groupB, , ,] = $this->publishedCommunityPost();
        $outsider = User::factory()->create();
        $this->addMemberToGroup($groupB, $outsider);

        Sanctum::actingAs($outsider);
        $this->getJson("/api/v1/posts/{$postA->id}/comments")->assertNotFound();
        $this->postJson("/api/v1/posts/{$postA->id}/comments", ['body' => 'Hola'])->assertForbidden();
    }

    public function test_suspended_member_cannot_post_comment(): void
    {
        [$group, , , $post] = $this->publishedCommunityPost();
        $suspended = User::factory()->create();
        \App\Domains\Neighborhoods\Models\GroupMember::factory()->create([
            'neighborhood_group_id' => $group->id,
            'municipality_id' => $group->municipality_id,
            'user_id' => $suspended->id,
            'status' => MembershipStatus::Suspended,
        ]);

        Sanctum::actingAs($suspended);
        $this->postJson("/api/v1/posts/{$post->id}/comments", ['body' => 'Hola'])->assertForbidden();
    }

    public function test_hidden_post_comments_not_found_for_unauthorized_reader(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        $member = User::factory()->create();
        $this->addMemberToGroup($group, $member);

        Sanctum::actingAs($moderator);
        app(HidePostService::class)->execute($post->fresh(), $moderator, 'moderación');

        $post = $post->fresh();
        $this->assertSame(PostStatus::Hidden, $post->status);

        Sanctum::actingAs($member);
        $this->getJson("/api/v1/posts/{$post->id}/comments")->assertNotFound();
    }

    public function test_comments_index_query_count_stays_bounded(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        Sanctum::actingAs($moderator);

        foreach (range(1, 12) as $i) {
            PostComment::query()->create([
                'post_id' => $post->id,
                'municipality_id' => $post->municipality_id,
                'author_id' => $author->id,
                'body' => "Comentario {$i}",
                'status' => PostCommentStatus::Visible,
            ]);
        }

        $queries = $this->countQueries(
            fn () => $this->getJson("/api/v1/posts/{$post->id}/comments")->assertOk(),
        );

        $this->assertLessThan(12, $queries);
    }

    public function test_post_domain_exception_renders_as_unprocessable_json(): void
    {
        $request = Request::create('/api/v1/posts/1/comments', 'POST');
        $request->headers->set('Accept', 'application/json');

        $exception = new PostDomainException('No se permiten comentarios en esta publicación.');
        $response = $this->app->make(\Illuminate\Contracts\Debug\ExceptionHandler::class)
            ->render($request, $exception);

        $this->assertSame(422, $response->getStatusCode());
        $this->assertSame(
            'No se permiten comentarios en esta publicación.',
            $response->getData(true)['message'],
        );
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