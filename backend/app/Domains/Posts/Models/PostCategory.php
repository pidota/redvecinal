<?php

namespace App\Domains\Posts\Models;

use App\Domains\Municipality\Models\Municipality;
use Database\Factories\PostCategoryFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\UseFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'municipality_id',
    'catalog_scope',
    'slug',
    'name',
    'description',
    'default_audience',
    'is_system',
    'is_active',
    'sort_order',
])]
#[UseFactory(PostCategoryFactory::class)]
class PostCategory extends Model
{
    use HasFactory;

    protected static function booted(): void
    {
        static::saving(function (PostCategory $category): void {
            if ($category->municipality_id === null) {
                $category->catalog_scope = 'global';
            } else {
                $category->catalog_scope = (string) $category->municipality_id;
            }
        });
    }

    public function municipality(): BelongsTo
    {
        return $this->belongsTo(Municipality::class);
    }
}
