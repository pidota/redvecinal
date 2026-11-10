<?php

namespace Tests\Feature\Posts\Filament;

use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostModerationEvent;
use App\Domains\Posts\Services\ApprovePostService;
use App\Domains\Posts\Services\CreateCommunityPostService;
use App\Domains\Posts\Services\SubmitPostService;
use App\Filament\Resources\CommunityPosts\CommunityPostResource;
use App\Domains\Posts\Exceptions\PostDomainException;
use App\Filament\Resources\CommunityPosts\Pages\ListCommunityPosts;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Features\SupportTesting\Testable;
use Livewire\Livewire;
use Spatie\Permission\Models\Role;
use Tests\Concerns\CreatesPostFixtures;
use Tests\Concerns\InteractsWithFilamentPanel;
use Tests\TestCase;

class CommunityPostFilamentTest extends TestCase
{
    use CreatesPostFixtures, InteractsWithFilamentPanel, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
        Role::findOrCreate('super-admin', 'web');
        Role::findOrCreate('administrador-municipal', 'web');
    }

    public function test_municipal_admin_sees_only_own_municipality_posts_in_list(): void
    {
        [$groupA, , , $postA] = $this->publishedCommunityPost();
        [$groupB, , , $postB] = $this->publishedCommunityPost();
        $adminA = $this->municipalAdministratorFor($groupA->municipality);
        $this->authenticateForFilament($adminA);

        $visibleIds = CommunityPostResource::getEloquentQuery()->pluck('id')->all();
        $this->assertContains($postA->id, $visibleIds);
        $this->assertNotContains($postB->id, $visibleIds);

        /** @var Testable $livewire */
        $livewire = Livewire::test(ListCommunityPosts::class);
        $livewire->assertCanSeeTableRecords([$postA]);
        $livewire->assertCanNotSeeTableRecords([$postB]);
    }

    public function test_hide_action_uses_domain_service_and_records_audit(): void
    {
        [$group, , , $post] = $this->publishedCommunityPost();
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(ListCommunityPosts::class)
            ->callTableAction('hide', $post);

        $post->refresh();
        $this->assertSame(PostStatus::Hidden, $post->status);
        $this->assertDatabaseHas('post_moderation_events', [
            'post_id' => $post->id,
            'event' => 'hidden',
        ]);
    }

    public function test_restore_action_restores_hidden_post(): void
    {
        [$group, , , $post] = $this->publishedCommunityPost();
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(ListCommunityPosts::class)
            ->callTableAction('hide', $post);

        Livewire::test(ListCommunityPosts::class)
            ->callTableAction('restore', $post->fresh());

        $this->assertSame(PostStatus::Published, $post->fresh()->status);
        $this->assertDatabaseHas('post_moderation_events', [
            'post_id' => $post->id,
            'event' => 'restored',
        ]);
    }

    public function test_municipal_admin_cannot_approve_via_hidden_livewire_endpoint(): void
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $admin = $this->municipalAdministratorFor($group->municipality);
        $post = app(CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->postCategory->id,
            'Pendiente',
            'Texto',
        );
        app(SubmitPostService::class)->execute($post, $author);
        $this->authenticateForFilament($admin);

        $this->assertFalse($admin->can('approve', $post->fresh()));

        $this->expectException(PostDomainException::class);
        app(ApprovePostService::class)->execute($post->fresh(), $admin);
    }

    public function test_foreign_municipal_admin_cannot_hide_community_post(): void
    {
        [$groupA, , , $post] = $this->publishedCommunityPost();
        [$groupB] = $this->activeGroupTriple();
        $adminB = $this->municipalAdministratorFor($groupB->municipality);
        $this->authenticateForFilament($adminB);

        $this->assertFalse($adminB->can('hide', $post));
    }
}
