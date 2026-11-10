<?php

namespace Tests\Feature\Posts;

use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Posts\Enums\PostRevisionStatus;
use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostCategory;
use App\Domains\Posts\Services\ApprovePostService;
use App\Domains\Posts\Services\CreateCommunityPostService;
use App\Domains\Posts\Services\RejectPostService;
use App\Domains\Posts\Services\SubmitPostService;
use App\Domains\Posts\Services\UpdatePostRevisionService;
use App\Models\User;
use Database\Seeders\PostCategorySeeder;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class PostModerationFlowTest extends TestCase
{
    use RefreshDatabase;

    protected PostCategory $category;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(PostCategorySeeder::class);
        $this->category = PostCategory::query()->where('slug', 'aviso-comunitario')->firstOrFail();
    }

    public function test_draft_submit_approve_flow(): void
    {
        [$group, $author, $moderator] = $this->groupWithRoles();
        $post = app(CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->category->id,
            'Título',
            'Cuerpo',
        );
        app(SubmitPostService::class)->execute($post, $author);
        $post->refresh();
        $this->assertSame(PostStatus::Pending, $post->status);

        $approved = app(ApprovePostService::class)->execute($post, $moderator);
        $this->assertSame(PostStatus::Published, $approved->status);
        $this->assertNotNull($approved->current_published_revision_id);
    }

    public function test_reject_and_resubmit(): void
    {
        [$group, $author, $moderator] = $this->groupWithRoles();
        $post = app(CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->category->id,
            'Título',
            'Cuerpo',
        );
        app(SubmitPostService::class)->execute($post, $author);
        app(RejectPostService::class)->execute($post->fresh(), $moderator, 'Incomplete');
        $post->refresh();
        $this->assertSame(PostStatus::Rejected, $post->status);

        app(UpdatePostRevisionService::class)->execute($post, $author, $this->category->id, 'Título 2', 'Cuerpo 2');
        app(SubmitPostService::class)->execute($post->fresh(), $author);
        $post->refresh();
        $this->assertSame(PostStatus::Pending, $post->status);
    }

    public function test_self_approval_is_forbidden(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $president = User::factory()->create();
        GroupMember::factory()->create([
            'neighborhood_group_id' => $group->id,
            'municipality_id' => $group->municipality_id,
            'user_id' => $president->id,
            'membership_role' => MembershipRole::President,
            'status' => MembershipStatus::Active,
        ]);

        $post = app(CreateCommunityPostService::class)->execute(
            $group,
            $president,
            $this->category->id,
            'Título',
            'Cuerpo',
        );
        app(SubmitPostService::class)->execute($post, $president);

        $this->expectExceptionMessage('No puede moderar sus propias propuestas');
        app(ApprovePostService::class)->execute($post->fresh(), $president);
    }

    public function test_amendment_keeps_published_until_approved(): void
    {
        [$group, $author, $moderator] = $this->groupWithRoles();
        $post = app(CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->category->id,
            'Original',
            'Contenido original',
        );
        app(SubmitPostService::class)->execute($post, $author);
        app(ApprovePostService::class)->execute($post->fresh(), $moderator);
        $publishedId = $post->fresh()->current_published_revision_id;

        app(UpdatePostRevisionService::class)->execute(
            $post->fresh(),
            $author,
            $this->category->id,
            'Nuevo título',
            'Nuevo cuerpo',
        );
        app(SubmitPostService::class)->execute($post->fresh(), $author);
        $post->refresh();

        $this->assertSame(PostStatus::Published, $post->status);
        $this->assertSame($publishedId, $post->current_published_revision_id);
        $this->assertTrue($post->pendingRevision()->exists());

        app(ApprovePostService::class)->execute($post->fresh(), $moderator);
        $post->refresh();
        $this->assertNotSame($publishedId, $post->current_published_revision_id);
        $this->assertSame('Nuevo título', $post->currentPublishedRevision->title);
    }

    public function test_api_returns_404_for_foreign_group_post(): void
    {
        [$groupA, $authorA, $moderatorA] = $this->groupWithRoles();
        [$groupB, $authorB] = $this->groupWithRoles();

        $post = app(CreateCommunityPostService::class)->execute(
            $groupA,
            $authorA,
            $this->category->id,
            'Privado',
            'Texto',
        );
        app(SubmitPostService::class)->execute($post, $authorA);
        app(ApprovePostService::class)->execute($post->fresh(), $moderatorA);

        Sanctum::actingAs($authorB);
        $this->getJson("/api/v1/posts/{$post->id}")->assertNotFound();
    }

    public function test_concurrent_approval_only_one_wins(): void
    {
        [$group, $author, $modA, $modB] = $this->groupWithModerators();
        $post = app(CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->category->id,
            'Título',
            'Cuerpo',
        );
        app(SubmitPostService::class)->execute($post, $author);

        app(ApprovePostService::class)->execute($post->fresh(), $modA);

        $this->expectExceptionMessage('No hay una revisión pendiente');
        app(ApprovePostService::class)->execute($post->fresh(), $modB);
    }

    private function groupWithRoles(): array
    {
        $group = NeighborhoodGroup::factory()->create();
        $author = User::factory()->create();
        $moderator = User::factory()->create();
        $admin = User::factory()->create();

        GroupMember::factory()->create([
            'neighborhood_group_id' => $group->id,
            'municipality_id' => $group->municipality_id,
            'user_id' => $author->id,
            'membership_role' => MembershipRole::Member,
            'status' => MembershipStatus::Active,
        ]);
        GroupMember::factory()->create([
            'neighborhood_group_id' => $group->id,
            'municipality_id' => $group->municipality_id,
            'user_id' => $moderator->id,
            'membership_role' => MembershipRole::Moderator,
            'status' => MembershipStatus::Active,
        ]);

        return [$group, $author, $moderator];
    }

    private function groupWithModerators(): array
    {
        $group = NeighborhoodGroup::factory()->create();
        $author = User::factory()->create();
        $modA = User::factory()->create();
        $modB = User::factory()->create();

        foreach ([$author, $modA, $modB] as $i => $user) {
            GroupMember::factory()->create([
                'neighborhood_group_id' => $group->id,
                'municipality_id' => $group->municipality_id,
                'user_id' => $user->id,
                'membership_role' => $i === 0 ? MembershipRole::Member : MembershipRole::Moderator,
                'status' => MembershipStatus::Active,
            ]);
        }

        return [$group, $author, $modA, $modB];
    }
}
