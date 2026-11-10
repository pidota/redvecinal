<?php

namespace App\Domains\Municipality\Models;

use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Database\Factories\MunicipalityFactory;
use Illuminate\Database\Eloquent\Attributes\UseFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable([
    'name',
    'slug',
    'region_code',
    'commune_code',
    'status',
    'settings',
])]
#[UseFactory(MunicipalityFactory::class)]
class Municipality extends Model
{
    use HasFactory;
    protected function casts(): array
    {
        return [
            'settings' => 'array',
        ];
    }

    public function neighborhoodGroups(): HasMany
    {
        return $this->hasMany(NeighborhoodGroup::class);
    }

    public function members(): HasMany
    {
        return $this->hasMany(MunicipalityMember::class);
    }
}
