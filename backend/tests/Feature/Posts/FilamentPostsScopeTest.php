<?php

namespace Tests\Feature\Posts;

use App\Domains\Posts\Services\PublishOfficialPostService;
use App\Filament\Pages\ModerationQueue;
use App\Filament\Resources\MunicipalPosts\MunicipalPostResource;
use App\Models\User;
use Filament\Facades\Filament;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Role;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class FilamentPostsScopeTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
        Role::findOrCreate('super-admin', 'web');
        Role::findOrCreate('administrador-municipal', 'web');
    }

    public function test_president_cannot_access_filament_panel(): void
    {
        $president = User::factory()->create();
        $this->assertFalse($president->canAccessPanel(Filament::getPanel('admin')));
    }

    public function test_super_admin_can_access_posts_resources(): void
    {
        $super = User::factory()->create();
        $super->assignRole('super-admin');
        $this->actingAs($super);

        $this->assertTrue(MunicipalPostResource::canViewAny());
        $this->assertTrue(ModerationQueue::canAccess());
    }

    public function test_municipal_admin_can_create_official_post_via_service(): void
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $admin = $this->municipalAdministratorFor($group->municipality);

        $post = app(PublishOfficialPostService::class)->execute(
            $group->municipality,
            $admin,
            $this->postCategory->id,
            'Comunicado',
            'Texto institucional',
        );

        $this->assertNull($post->neighborhood_group_id);
        $this->assertTrue($post->isMunicipal());
    }

    public function test_moderation_queue_is_accessible_for_municipal_admin(): void
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $admin = $this->municipalAdministratorFor($group->municipality);
        $admin->givePermissionTo('posts.community.view');

        $this->actingAs($admin);
        $this->assertTrue(ModerationQueue::canAccess());
    }
}
