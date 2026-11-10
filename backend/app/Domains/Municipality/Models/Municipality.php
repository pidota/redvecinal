<?php

namespace App\Domains\Municipality\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;

#[Fillable([
    'name',
    'slug',
    'region_code',
    'commune_code',
    'status',
    'settings',
])]
class Municipality extends Model
{
    protected function casts(): array
    {
        return [
            'settings' => 'array',
        ];
    }
}
