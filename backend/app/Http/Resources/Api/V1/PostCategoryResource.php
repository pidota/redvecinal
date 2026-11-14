<?php

namespace App\Http\Resources\Api\V1;

use App\Domains\Posts\Models\PostCategory;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin PostCategory */
class PostCategoryResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'slug' => $this->slug,
            'name' => $this->name,
            'description' => $this->description,
            'default_audience' => $this->default_audience,
            'sort_order' => $this->sort_order,
            'is_system' => $this->is_system,
        ];
    }
}