<?php

namespace Tests\Feature;

use App\Domains\Municipality\Models\Municipality;
use Database\Seeders\MunicipalitySeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class MunicipalitySeederTest extends TestCase
{
    use RefreshDatabase;

    public function test_chepica_municipality_is_seeded_idempotently(): void
    {
        $this->seed(MunicipalitySeeder::class);
        $this->seed(MunicipalitySeeder::class);

        $this->assertDatabaseCount('municipalities', 1);

        $municipality = Municipality::query()->where('slug', 'chepica')->first();

        $this->assertNotNull($municipality);
        $this->assertSame('Municipalidad de Chépica', $municipality->name);
        $this->assertSame('06', $municipality->region_code);
        $this->assertSame('06302', $municipality->commune_code);
        $this->assertSame('active', $municipality->status);
    }
}
