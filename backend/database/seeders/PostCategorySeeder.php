<?php

namespace Database\Seeders;

use App\Domains\Posts\Models\PostCategory;
use Illuminate\Database\Seeder;

class PostCategorySeeder extends Seeder
{
    public const GLOBAL_CATEGORIES = [
        ['slug' => 'comunicado-municipal', 'name' => 'Comunicado municipal', 'default_audience' => 'municipal', 'sort_order' => 1],
        ['slug' => 'aviso-comunitario', 'name' => 'Aviso comunitario', 'default_audience' => 'group', 'sort_order' => 2],
        ['slug' => 'actividad-evento', 'name' => 'Actividad o evento', 'default_audience' => 'group', 'sort_order' => 3],
        ['slug' => 'informacion-general', 'name' => 'Información general', 'default_audience' => 'group', 'sort_order' => 4],
        ['slug' => 'solicitud-colaboracion', 'name' => 'Solicitud de colaboración', 'default_audience' => 'group', 'sort_order' => 5],
    ];

    public function run(): void
    {
        foreach (self::GLOBAL_CATEGORIES as $category) {
            PostCategory::query()->updateOrCreate(
                [
                    'catalog_scope' => 'global',
                    'slug' => $category['slug'],
                ],
                [
                    'municipality_id' => null,
                    'name' => $category['name'],
                    'default_audience' => $category['default_audience'],
                    'is_system' => true,
                    'is_active' => true,
                    'sort_order' => $category['sort_order'],
                ],
            );
        }
    }
}
