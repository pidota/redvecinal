<?php

namespace Database\Factories;

use App\Domains\Municipality\Models\Municipality;
use Illuminate\Database\Eloquent\Factories\Factory;
use Illuminate\Support\Str;

/**
 * @extends Factory<Municipality>
 */
class MunicipalityFactory extends Factory
{
    protected $model = Municipality::class;

    public function definition(): array
    {
        $name = $this->faker->unique()->city();

        return [
            'name' => $name,
            'slug' => Str::slug($name),
            'region_code' => '06',
            'commune_code' => $this->faker->numerify('06###'),
            'status' => 'active',
        ];
    }
}
