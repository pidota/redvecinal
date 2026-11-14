<?php

namespace Tests\Feature\Posts;

use App\Domains\Municipality\Models\Municipality;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Posts\Models\PostCategory;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class PostCategoryApiTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_lists_active_categories_for_member(): void
    {
        [, $member] = $this->activeGroupTriple();

        Sanctum::actingAs($member);
        $response = $this->getJson('/api/v1/post-categories')->assertOk();

        $slugs = collect($response->json('data'))->pluck('slug');
        $this->assertTrue($slugs->contains('aviso-comunitario'));
        $this->assertTrue($slugs->contains('comunicado-municipal'));

        $inactive = PostCategory::query()->where('slug', 'aviso-comunitario')->firstOrFail();
        $inactive->update(['is_active' => false]);

        $response = $this->getJson('/api/v1/post-categories')->assertOk();
        $this->assertFalse(collect($response->json('data'))->pluck('slug')->contains('aviso-comunitario'));
    }

    public function test_audience_filter(): void
    {
        [, $member] = $this->activeGroupTriple();

        Sanctum::actingAs($member);
        $response = $this->getJson('/api/v1/post-categories?audience=group')->assertOk();

        foreach ($response->json('data') as $category) {
            $this->assertSame('group', $category['default_audience']);
        }
    }

    public function test_foreign_municipality_category_is_excluded(): void
    {
        $municipalityA = Municipality::factory()->create();
        $municipalityB = Municipality::factory()->create();
        $group = NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityA->id]);
        $member = User::factory()->create();
        $this->addMemberToGroup($group, $member);

        PostCategory::query()->create([
            'municipality_id' => $municipalityB->id,
            'slug' => 'local-b',
            'name' => 'Local B',
            'default_audience' => 'group',
            'is_system' => false,
            'is_active' => true,
            'sort_order' => 99,
        ]);

        Sanctum::actingAs($member);
        $slugs = collect($this->getJson('/api/v1/post-categories')->json('data'))->pluck('slug');

        $this->assertFalse($slugs->contains('local-b'));
    }

    public function test_forbidden_without_membership(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $this->getJson('/api/v1/post-categories')->assertForbidden();
    }
}