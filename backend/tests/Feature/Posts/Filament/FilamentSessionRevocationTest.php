<?php

namespace Tests\Feature\Posts\Filament;

use App\Domains\Municipality\Enums\MunicipalityMemberStatus;
use App\Domains\Municipality\Models\MunicipalityMember;
use App\Domains\Posts\Models\Post;
use App\Filament\Resources\CommunityPosts\CommunityPostResource;
use App\Filament\Resources\CommunityPosts\Pages\ListCommunityPosts;
use App\Filament\Resources\MunicipalPosts\MunicipalPostResource;
use App\Filament\Resources\MunicipalPosts\Pages\CreateMunicipalPost;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Spatie\Permission\Models\Role;
use Tests\Concerns\CreatesPostFixtures;
use Tests\Concerns\InteractsWithFilamentPanel;
use Tests\TestCase;

class FilamentSessionRevocationTest extends TestCase
{
    use CreatesPostFixtures, InteractsWithFilamentPanel, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
        Role::findOrCreate('administrador-municipal', 'web');
    }

    public function test_revoked_municipal_membership_blocks_subsequent_filament_create(): void
    {
        [$group] = $this->activeGroupTriple();
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(CreateMunicipalPost::class)->assertSuccessful();

        $member = MunicipalityMember::query()
            ->where('user_id', $admin->id)
            ->where('municipality_id', $group->municipality_id)
            ->firstOrFail();
        $member->update(['status' => MunicipalityMemberStatus::Inactive]);

        $this->assertFalse($admin->fresh()->hasRole('administrador-municipal'));
        $this->authenticateForFilament($admin->fresh());
        $this->assertFalse(MunicipalPostResource::canCreate());

        Livewire::test(CreateMunicipalPost::class)->assertForbidden();
    }

    public function test_revoked_municipal_membership_blocks_hide_action_on_next_livewire_request(): void
    {
        [$group, , , $post] = $this->publishedCommunityPost();
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(ListCommunityPosts::class)->assertSuccessful();

        $member = MunicipalityMember::query()
            ->where('user_id', $admin->id)
            ->firstOrFail();
        $member->update(['status' => MunicipalityMemberStatus::Inactive]);

        $this->authenticateForFilament($admin->fresh());
        $this->assertFalse(CommunityPostResource::canViewAny());

        Livewire::test(ListCommunityPosts::class)
            ->assertForbidden();
    }

    public function test_revoked_admin_cannot_create_municipal_post_even_with_stale_form_state(): void
    {
        [$groupA] = $this->activeGroupTriple();
        [$groupB] = $this->activeGroupTriple();
        $admin = $this->municipalAdministratorFor($groupA->municipality);
        $this->authenticateForFilament($admin);

        $component = Livewire::test(CreateMunicipalPost::class)
            ->set('data.municipality_id', $groupA->municipality_id)
            ->set('data.category_id', $this->postCategory->id)
            ->set('data.title', 'Tras revocación')
            ->set('data.body', 'Contenido');

        MunicipalityMember::query()
            ->where('user_id', $admin->id)
            ->firstOrFail()
            ->update(['status' => MunicipalityMemberStatus::Inactive]);

        $this->authenticateForFilament($admin->fresh());

        $component->call('create');

        $this->assertFalse(
            Post::query()
                ->whereNull('neighborhood_group_id')
                ->where('author_id', $admin->id)
                ->where('municipality_id', $groupB->municipality_id)
                ->exists()
        );
        $this->assertFalse(
            Post::query()
                ->whereNull('neighborhood_group_id')
                ->where('author_id', $admin->id)
                ->whereHas('revisions', fn ($q) => $q->where('title', 'Tras revocación'))
                ->exists()
        );
    }
}
