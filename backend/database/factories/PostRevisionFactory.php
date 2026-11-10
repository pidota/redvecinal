<?php

namespace Database\Factories;

use App\Domains\Posts\Enums\PostRevisionStatus;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostCategory;
use App\Domains\Posts\Models\PostRevision;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<PostRevision>
 */
class PostRevisionFactory extends Factory
{
    protected $model = PostRevision::class;

    public function definition(): array
    {
        return [
            'post_id' => Post::factory(),
            'municipality_id' => fn (array $attributes) => Post::query()->find($attributes['post_id'])->municipality_id,
            'revision_number' => 1,
            'category_id' => PostCategory::factory(),
            'title' => fake()->sentence(4),
            'body' => fake()->paragraph(),
            'status' => PostRevisionStatus::Draft,
            'created_by' => User::factory(),
        ];
    }
}
