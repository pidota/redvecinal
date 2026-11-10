<?php

namespace Database\Seeders;

use App\Domains\Municipality\Models\Municipality;
use Illuminate\Database\Seeder;

class MunicipalitySeeder extends Seeder
{
    public function run(): void
    {
        Municipality::query()->updateOrCreate(
            ['slug' => 'chepica'],
            [
                'name' => 'Municipalidad de Chépica',
                'region_code' => '06',
                'commune_code' => '06302',
                'status' => 'active',
                'settings' => [
                    'country' => 'CL',
                    'display_name' => 'Chépica',
                ],
            ],
        );
    }
}
