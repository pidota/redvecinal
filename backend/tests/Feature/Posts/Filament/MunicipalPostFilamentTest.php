<?php

namespace Tests\Feature\Posts\Filament;

use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostModerationEvent;
use App\Filament\Resources\MunicipalPosts\MunicipalPostResource;
use App\Filament\Resources\MunicipalPosts\Pages\CreateMunicipalPost;
use App\Filament\Resources\MunicipalPosts\Pages\ListMunicipalPosts;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Spatie\Permission\Models\Role;
use Tests\Concerns\CreatesPostFixtures;
use Tests\Concerns\InteractsWithFilamentPanel;
use Tests\TestCase;

class MunicipalPostFilamentTest extends TestCase
{
    use CreatesPostFixtures, InteractsWithFilamentPanel, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
        Role::findOrCreate('super-admin', 'web');
        Role::findOrCreate('administrador-municipal', 'web');
    }

    public function test_super_admin_can_access_municipal_posts_resource(): void
    {
        $super = User::factory()->create();
        $super->assignRole('super-admin');
        $this->authenticateForFilament($super);

        $this->assertTrue(MunicipalPostResource::canViewAny());
        $this->assertTrue(MunicipalPostResource::canCreate());

        Livewire::test(ListMunicipalPosts::class)->assertSuccessful();
        Livewire::test(CreateMunicipalPost::class)->assertSuccessful();
    }

    public function test_municipal_admin_can_create_official_post_via_filament_create_page(): void
    {
        [$group] = $this->activeGroupTriple();
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(CreateMunicipalPost::class)
            ->set('data.municipality_id', $group->municipality_id)
            ->set('data.category_id', $this->postCategory->id)
            ->set('data.title', 'Comunicado oficial prueba')
            ->set('data.body', 'Contenido **markdown** de prueba.')
            ->set('data.comments_enabled', true)
            ->call('create')
            ->assertHasNoErrors();

        $post = Post::query()->whereNull('neighborhood_group_id')->latest('id')->first();
        $this->assertNotNull($post);
        $this->assertSame(PostStatus::Published, $post->status);
        $this->assertSame($group->municipality_id, $post->municipality_id);
        $this->assertSame('Comunicado oficial prueba', $post->currentPublishedRevision?->title);
        $this->assertDatabaseHas('post_moderation_events', [
            'post_id' => $post->id,
            'event' => 'municipal_published',
        ]);
    }

    public function test_municipal_admin_cannot_create_in_other_municipality_via_livewire(): void
    {
        [$groupA] = $this->activeGroupTriple();
        [$groupB] = $this->activeGroupTriple();
        $adminA = $this->municipalAdministratorFor($groupA->municipality);
        $this->authenticateForFilament($adminA);

        Livewire::test(CreateMunicipalPost::class)
            ->set('data.municipality_id', $groupB->municipality_id)
            ->set('data.category_id', $this->postCategory->id)
            ->set('data.title', 'Intento indebido')
            ->set('data.body', 'Texto')
            ->call('create');

        $this->assertDatabaseMissing('post_revisions', [
            'title' => 'Intento indebido',
        ]);
        $this->assertFalse(
            Post::query()
                ->whereNull('neighborhood_group_id')
                ->where('municipality_id', $groupB->municipality_id)
                ->where('author_id', $adminA->id)
                ->exists()
        );
    }

    public function test_unauthorized_user_cannot_use_municipal_posts_resource(): void
    {
        $vecino = User::factory()->create();
        $this->authenticateForFilament($vecino);

        $this->assertFalse(MunicipalPostResource::canViewAny());
        $this->assertFalse(MunicipalPostResource::canCreate());
    }

    public function test_form_validation_requires_title_body_and_category(): void
    {
        [$group] = $this->activeGroupTriple();
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(CreateMunicipalPost::class)
            ->set('data.municipality_id', $group->municipality_id)
            ->set('data.title', '')
            ->set('data.body', '')
            ->call('create')
            ->assertHasErrors(['data.title', 'data.body']);
    }
}
