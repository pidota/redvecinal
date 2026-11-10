<?php

namespace Tests\Feature\Posts;

use App\Domains\Municipality\Models\Municipality;
use App\Domains\Neighborhoods\Enums\NeighborhoodGroupStatus;
use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Services\HidePostService;
use App\Domains\Posts\Services\RestorePostService;
use App\Filament\Resources\CommunityPosts\CommunityPostResource;
use App\Models\User;
use Filament\Facades\Filament;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Spatie\Permission\Models\Role;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class PostMunicipalIsolationTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_municipal_admin_cannot_hide_post_in_other_municipality(): void
    {
        [$groupA, $author, $moderator, $post] = $this->publishedCommunityPost();
        $municipalityB = Municipality::factory()->create();
        $adminB = $this->municipalAdministratorFor($municipalityB);

        $this->assertFalse($adminB->can('hide', $post));
    }

    public function test_foreign_municipal_admin_cannot_hide_via_domain_service(): void
    {
        [$groupA, , , $post] = $this->publishedCommunityPost();
        $municipalityB = Municipality::factory()->create();
        $adminB = $this->municipalAdministratorFor($municipalityB);

        $this->expectException(\Illuminate\Auth\Access\AuthorizationException::class);
        app(HidePostService::class)->execute($post, $adminB, 'Intento indebido');
    }

    public function test_foreign_member_gets_404_on_other_municipality_post(): void
    {
        $municipalityA = Municipality::factory()->create(['slug' => 'muni-a']);
        $municipalityB = Municipality::factory()->create(['slug' => 'muni-b']);
        $groupA = \App\Domains\Neighborhoods\Models\NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityA->id]);
        $author = User::factory()->create();
        $moderator = User::factory()->create();
        $this->addMemberToGroup($groupA, $author);
        $this->addMemberToGroup($groupA, $moderator, \App\Domains\Neighborhoods\Enums\MembershipRole::Moderator);

        $post = app(\App\Domains\Posts\Services\CreateCommunityPostService::class)->execute(
            $groupA,
            $author,
            $this->postCategory->id,
            'Local',
            'Solo A',
        );
        app(\App\Domains\Posts\Services\SubmitPostService::class)->execute($post, $author);
        app(\App\Domains\Posts\Services\ApprovePostService::class)->execute($post->fresh(), $moderator);

        $groupB = \App\Domains\Neighborhoods\Models\NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityB->id]);
        $vecinoB = User::factory()->create();
        $this->addMemberToGroup($groupB, $vecinoB);

        Sanctum::actingAs($vecinoB);
        $this->getJson("/api/v1/posts/{$post->id}")->assertNotFound();
    }

    public function test_municipal_admin_can_hide_own_municipality_post(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        $admin = $this->municipalAdministratorFor($group->municipality);

        app(HidePostService::class)->execute($post, $admin, 'Supervisión municipal');
        $this->assertSame(PostStatus::Hidden, $post->fresh()->status);

        app(RestorePostService::class)->execute($post->fresh(), $admin);
        $this->assertSame(PostStatus::Published, $post->fresh()->status);
    }

    public function test_pending_queue_forbidden_for_foreign_group_moderator(): void
    {
        [$groupA, $authorA, $modA] = $this->activeGroupTriple();
        $post = app(\App\Domains\Posts\Services\CreateCommunityPostService::class)->execute(
            $groupA,
            $authorA,
            $this->postCategory->id,
            'Pendiente',
            'Texto',
        );
        app(\App\Domains\Posts\Services\SubmitPostService::class)->execute($post, $authorA);

        [$groupB, $authorB, $modB] = $this->activeGroupTriple();
        Sanctum::actingAs($modB);
        $this->getJson("/api/v1/groups/{$groupA->id}/posts/pending")->assertForbidden();
    }

    public function test_filament_community_posts_scoped_to_municipality(): void
    {
        Role::findOrCreate('administrador-municipal', 'web');
        [$groupA, , , $postA] = $this->publishedCommunityPost();
        [$groupB, , , $postB] = $this->publishedCommunityPost();
        $adminA = $this->municipalAdministratorFor($groupA->municipality);

        $this->actingAs($adminA);
        Filament::auth()->login($adminA);

        $ids = CommunityPostResource::getEloquentQuery()->pluck('id')->all();

        $this->assertContains($postA->id, $ids);
        $this->assertNotContains($postB->id, $ids);
    }
}
