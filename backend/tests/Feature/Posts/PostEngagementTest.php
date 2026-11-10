<?php

namespace Tests\Feature\Posts;

use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Enums\NeighborhoodGroupStatus;
use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Exceptions\PostDomainException;
use App\Domains\Posts\Models\PostReaction;
use App\Domains\Posts\Services\AddCommentService;
use App\Domains\Posts\Services\ReportPostService;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class PostEngagementTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_cannot_comment_on_pending_post(): void
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $post = app(\App\Domains\Posts\Services\CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->postCategory->id,
            'Pendiente',
            'Texto',
        );
        app(\App\Domains\Posts\Services\SubmitPostService::class)->execute($post, $author);

        $this->expectException(PostDomainException::class);
        app(AddCommentService::class)->execute($post->fresh(), $moderator, 'Hola');
    }

    public function test_suspended_member_cannot_comment(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
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

    public function test_suspended_group_blocks_new_comments(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        $group->update(['status' => NeighborhoodGroupStatus::Suspended]);
        $member = User::factory()->create();
        $this->addMemberToGroup($group, $member);

        Sanctum::actingAs($member);
        $this->postJson("/api/v1/posts/{$post->id}/comments", ['body' => 'Hola'])->assertForbidden();
    }

    public function test_reaction_is_unique_per_user(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        $member = User::factory()->create();
        $this->addMemberToGroup($group, $member);

        Sanctum::actingAs($member);
        $this->putJson("/api/v1/posts/{$post->id}/reactions", ['type' => 'like'])->assertOk();
        $this->putJson("/api/v1/posts/{$post->id}/reactions", ['type' => 'like'])->assertOk();

        $this->assertSame(1, PostReaction::query()->where('post_id', $post->id)->where('user_id', $member->id)->count());
    }

    public function test_report_response_does_not_expose_reporter(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        $reporter = User::factory()->create();
        $this->addMemberToGroup($group, $reporter);

        Sanctum::actingAs($reporter);
        $response = $this->postJson("/api/v1/posts/{$post->id}/reports", [
            'reason_code' => 'spam',
            'details' => 'Contenido dudoso',
        ]);

        $response->assertCreated();
        $response->assertJsonMissing(['reporter_id']);
        $response->assertJsonStructure(['id', 'status']);
    }

    public function test_report_is_linked_to_post(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        $reporter = User::factory()->create();
        $this->addMemberToGroup($group, $reporter);

        $record = app(ReportPostService::class)->execute($reporter, 'inappropriate', $post, null, 'Detalle');
        $this->assertSame($post->id, $record->post_id);
    }

    public function test_comments_on_foreign_private_post_return_404(): void
    {
        [$groupA, $authorA, $modA, $postA] = $this->publishedCommunityPost();
        [$groupB, , , $postB] = $this->publishedCommunityPost();
        $outsider = User::factory()->create();
        $this->addMemberToGroup($groupB, $outsider);

        Sanctum::actingAs($outsider);
        $this->getJson("/api/v1/posts/{$postA->id}/comments")->assertNotFound();
    }
}
