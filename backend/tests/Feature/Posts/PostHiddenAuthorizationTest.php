<?php

namespace Tests\Feature\Posts;

use App\Domains\Municipality\Models\Municipality;
use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Posts\Enums\PostRevisionStatus;
use App\Domains\Posts\Models\PostAttachment;
use App\Domains\Posts\Models\PostCategory;
use App\Domains\Posts\Models\PostRevision;
use App\Domains\Posts\Services\AttachPostFileService;
use App\Domains\Posts\Services\HidePostService;
use App\Domains\Posts\Services\PublishOfficialPostService;
use App\Domains\Posts\Services\RestorePostService;
use App\Domains\Posts\Services\SubmitPostService;
use App\Domains\Posts\Services\UpdatePostRevisionService;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Spatie\Permission\Models\Role;
use Spatie\Permission\PermissionRegistrar;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class PostHiddenAuthorizationTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
        Storage::fake('posts_private');
    }

    public function test_published_community_post_visible_to_group_member_before_hide(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        $reader = User::factory()->create();
        $this->addMemberToGroup($group, $reader);

        Sanctum::actingAs($reader);
        $this->getJson("/api/v1/posts/{$post->id}")->assertOk();
    }

    public function test_hidden_community_post_returns_404_for_group_member(): void
    {
        [$group, $author, $moderator, $post, , $attachment] = $this->communityPostWithPublishedAttachment();
        $reader = User::factory()->create();
        $this->addMemberToGroup($group, $reader);

        app(HidePostService::class)->execute($post->fresh(), $moderator, 'Moderación');

        Sanctum::actingAs($reader);
        $this->getJson("/api/v1/posts/{$post->id}")->assertNotFound();
        $this->getJson("/api/v1/posts/{$post->id}/attachments/{$attachment->id}")->assertNotFound();
    }

    public function test_author_retains_view_on_hidden_community_post(): void
    {
        [$group, $author, $moderator, $post, , $attachment] = $this->communityPostWithPublishedAttachment();
        app(HidePostService::class)->execute($post->fresh(), $moderator, 'Moderación');

        Sanctum::actingAs($author);
        $this->getJson("/api/v1/posts/{$post->id}")->assertOk();
        $this->getJson("/api/v1/posts/{$post->id}/attachments/{$attachment->id}")->assertOk();
    }

    public function test_moderator_retains_view_and_attachment_on_hidden_post(): void
    {
        [$group, $author, $moderator, $post, , $attachment] = $this->communityPostWithPublishedAttachment();
        app(HidePostService::class)->execute($post->fresh(), $moderator, 'Moderación');

        Sanctum::actingAs($moderator);
        $this->getJson("/api/v1/posts/{$post->id}")->assertOk();
        $this->getJson("/api/v1/posts/{$post->id}/attachments/{$attachment->id}")->assertOk();
    }

    public function test_president_retains_view_on_hidden_community_post(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        $president = User::factory()->create();
        $this->addMemberToGroup($group, $president, MembershipRole::President);

        app(HidePostService::class)->execute($post->fresh(), $moderator, 'Moderación');

        Sanctum::actingAs($president);
        $this->getJson("/api/v1/posts/{$post->id}")->assertOk();
    }

    public function test_municipal_admin_with_hide_permission_retains_view_on_hidden_community_post(): void
    {
        [$group, $author, $moderator, $post, , $attachment] = $this->communityPostWithPublishedAttachment();
        $admin = $this->municipalAdministratorFor($group->municipality);

        app(HidePostService::class)->execute($post->fresh(), $admin, 'Supervisión municipal');

        Sanctum::actingAs($admin);
        $this->getJson("/api/v1/posts/{$post->id}")->assertOk();
        $this->getJson("/api/v1/posts/{$post->id}/attachments/{$attachment->id}")->assertOk();
    }

    public function test_municipal_operator_without_hide_permissions_cannot_view_hidden_post(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();

        $role = Role::findByName('administrador-municipal', 'web');
        $role->revokePermissionTo(['posts.community.hide', 'posts.municipal.hide']);
        app(PermissionRegistrar::class)->forgetCachedPermissions();

        $admin = $this->municipalAdministratorFor($group->municipality);

        app(HidePostService::class)->execute($post->fresh(), $moderator, 'Moderación');

        Sanctum::actingAs($admin);
        $this->getJson("/api/v1/posts/{$post->id}")->assertNotFound();
    }

    public function test_foreign_group_member_gets_404_on_hidden_post(): void
    {
        [$groupA, $author, $moderator, $post] = $this->publishedCommunityPost();
        [$groupB, $outsider] = $this->foreignGroupMember();

        app(HidePostService::class)->execute($post->fresh(), $moderator, 'Moderación');

        $this->addMemberToGroup($groupB, $outsider);
        Sanctum::actingAs($outsider);
        $this->getJson("/api/v1/posts/{$post->id}")->assertNotFound();
    }

    public function test_foreign_municipality_member_gets_404_on_hidden_post(): void
    {
        $municipalityA = Municipality::factory()->create(['slug' => 'muni-hide-a']);
        $municipalityB = Municipality::factory()->create(['slug' => 'muni-hide-b']);
        $groupA = \App\Domains\Neighborhoods\Models\NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityA->id]);
        $author = User::factory()->create();
        $moderator = User::factory()->create();
        $this->addMemberToGroup($groupA, $author);
        $this->addMemberToGroup($groupA, $moderator, MembershipRole::Moderator);

        $post = app(\App\Domains\Posts\Services\CreateCommunityPostService::class)->execute(
            $groupA,
            $author,
            $this->postCategory->id,
            'Local',
            'Cuerpo',
        );
        app(SubmitPostService::class)->execute($post, $author);
        app(\App\Domains\Posts\Services\ApprovePostService::class)->execute($post->fresh(), $moderator);

        $groupB = \App\Domains\Neighborhoods\Models\NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityB->id]);
        $vecinoB = User::factory()->create();
        $this->addMemberToGroup($groupB, $vecinoB);

        app(HidePostService::class)->execute($post->fresh(), $moderator, 'Ocultar');

        Sanctum::actingAs($vecinoB);
        $this->getJson("/api/v1/posts/{$post->id}")->assertNotFound();
    }

    public function test_user_without_membership_gets_404_on_hidden_post(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        app(HidePostService::class)->execute($post->fresh(), $moderator, 'Ocultar');

        $stranger = User::factory()->create();
        Sanctum::actingAs($stranger);
        $this->getJson("/api/v1/posts/{$post->id}")->assertNotFound();
    }

    public function test_hidden_municipal_post_returns_404_for_municipality_member(): void
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
        $group = \App\Domains\Neighborhoods\Models\NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id]);
        $this->addMemberToGroup($group, $member);

        app(HidePostService::class)->execute($post->fresh(), $admin, 'Retirar');

        Sanctum::actingAs($member);
        $this->getJson("/api/v1/posts/{$post->id}")->assertNotFound();
    }

    public function test_restore_hidden_post_restores_member_access(): void
    {
        [$group, $author, $moderator, $post, , $attachment] = $this->communityPostWithPublishedAttachment();
        $reader = User::factory()->create();
        $this->addMemberToGroup($group, $reader);

        app(HidePostService::class)->execute($post->fresh(), $moderator, 'Temporal');
        Sanctum::actingAs($reader);
        $this->getJson("/api/v1/posts/{$post->id}")->assertNotFound();

        app(RestorePostService::class)->execute($post->fresh(), $moderator);

        $this->getJson("/api/v1/posts/{$post->id}")->assertOk();
        $this->getJson("/api/v1/posts/{$post->id}/attachments/{$attachment->id}")->assertOk();
    }

    public function test_feed_excludes_hidden_posts(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        app(HidePostService::class)->execute($post->fresh(), $moderator, 'Fuera del feed');

        Sanctum::actingAs($author);
        $response = $this->getJson('/api/v1/posts')->assertOk();
        $ids = collect($response->json('data'))->pluck('id')->all();

        $this->assertNotContains($post->id, $ids);
    }

    public function test_author_sees_hidden_post_in_mine_endpoint(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        app(HidePostService::class)->execute($post->fresh(), $moderator, 'Ocultar');

        Sanctum::actingAs($author);
        $response = $this->getJson('/api/v1/me/posts')->assertOk();
        $ids = collect($response->json('data'))->pluck('id')->all();

        $this->assertContains($post->id, $ids);
        $this->getJson("/api/v1/posts/{$post->id}")->assertOk();
    }

    public function test_pending_revision_attachment_still_forbidden_for_reader_on_hidden_published_post(): void
    {
        [$group, $author, $moderator, $post, , $publishedAttachment] = $this->communityPostWithPublishedAttachment();
        $reader = User::factory()->create();
        $this->addMemberToGroup($group, $reader);

        app(UpdatePostRevisionService::class)->execute(
            $post,
            $author,
            $this->postCategory->id,
            'Enmienda',
            'Nuevo cuerpo',
        );
        $pending = PostRevision::query()
            ->where('post_id', $post->id)
            ->where('status', PostRevisionStatus::Draft)
            ->firstOrFail();
        $pendingAttachment = $this->storePdf($pending, $author);
        app(SubmitPostService::class)->execute($post->fresh(), $author);

        app(HidePostService::class)->execute($post->fresh(), $moderator, 'Ocultar');

        Sanctum::actingAs($reader);
        $this->getJson("/api/v1/posts/{$post->id}")->assertNotFound();
        $this->getJson("/api/v1/posts/{$post->id}/attachments/{$publishedAttachment->id}")->assertNotFound();
        $this->getJson("/api/v1/posts/{$post->id}/attachments/{$pendingAttachment->id}")->assertNotFound();
    }

    /**
     * @return array{0: \App\Domains\Neighborhoods\Models\NeighborhoodGroup, 1: User, 2: User, 3: \App\Domains\Posts\Models\Post, 4: PostRevision, 5: PostAttachment}
     */
    private function communityPostWithPublishedAttachment(): array
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $post = app(\App\Domains\Posts\Services\CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->postCategory->id,
            'Con adjunto',
            'Cuerpo',
        );
        $revision = $post->revisions()->firstOrFail();
        $attachment = $this->storePdf($revision, $author);
        app(SubmitPostService::class)->execute($post, $author);
        app(\App\Domains\Posts\Services\ApprovePostService::class)->execute($post->fresh(), $moderator);
        $post = $post->fresh(['currentPublishedRevision', 'neighborhoodGroup']);

        return [$group, $author, $moderator, $post, $revision->fresh(), $attachment->fresh()];
    }

    /**
     * @return array{0: \App\Domains\Neighborhoods\Models\NeighborhoodGroup, 1: User}
     */
    private function foreignGroupMember(): array
    {
        $group = \App\Domains\Neighborhoods\Models\NeighborhoodGroup::factory()->create();
        $user = User::factory()->create();

        return [$group, $user];
    }

    private function storePdf(PostRevision $revision, User $user): PostAttachment
    {
        $file = UploadedFile::fake()->createWithContent('doc.pdf', "%PDF-1.4\n%%EOF");

        return app(AttachPostFileService::class)->execute($revision, $user, $file);
    }
}