<?php

namespace Database\Factories;

use App\Domains\Posts\Models\PostCategory;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/**
 * @extends Factory<PostCategory>
 */
class PostCategoryFactory extends Factory
{
    protected $model = PostCategory::class;

    public function definition(): array
    {
        $slug = Str::slug(fake()->unique()->words(2, true));

        return [
            'municipality_id' => null,
            'catalog_scope' => 'global',
            'slug' => $slug,
            'name' => fake()->sentence(2),
            'description' => fake()->optional()->sentence(),
            'default_audience' => 'group',
            'is_system' => false,
            'is_active' => true,
            'sort_order' => 0,
        ];
    }
}
