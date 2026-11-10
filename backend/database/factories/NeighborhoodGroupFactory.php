<?php

namespace Database\Factories;

use App\Domains\Municipality\Models\Municipality;
use App\Domains\Neighborhoods\Enums\NeighborhoodGroupStatus;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/**
 * @extends Factory<NeighborhoodGroup>
 */
class NeighborhoodGroupFactory extends Factory
{
    protected $model = NeighborhoodGroup::class;

    public function definition(): array
    {
        $name = 'Junta '.$this->faker->unique()->numerify('###');

        return [
            'municipality_id' => Municipality::factory(),
            'name' => $name,
            'slug' => Str::slug($name),
            'status' => NeighborhoodGroupStatus::Active,
        ];
    }

    public function suspended(): static
    {
        return $this->state(fn () => ['status' => NeighborhoodGroupStatus::Suspended]);
    }
}
