<?php

namespace Database\Factories;

use App\Domains\Municipality\Models\Municipality;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Enums\PostVisibility;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostCategory;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Post>
 */
class PostFactory extends Factory
{
    protected $model = Post::class;

    public function definition(): array
    {
        $group = NeighborhoodGroup::factory()->create();

        return [
            'municipality_id' => $group->municipality_id,
            'neighborhood_group_id' => $group->id,
            'author_id' => User::factory(),
            'category_id' => PostCategory::factory(),
            'status' => PostStatus::Draft,
            'visibility' => PostVisibility::MembersOnly,
            'comments_enabled' => true,
        ];
    }

    public function municipal(): static
    {
        return $this->state(function () {
            $municipality = Municipality::factory()->create();

            return [
                'municipality_id' => $municipality->id,
                'neighborhood_group_id' => null,
                'visibility' => PostVisibility::MunicipalFeed,
            ];
        });
    }
}
