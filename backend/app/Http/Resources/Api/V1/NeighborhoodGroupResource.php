<?php

namespace App\Http\Resources\Api\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class NeighborhoodGroupResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'municipality_id' => $this->municipality_id,
            'name' => $this->name,
            'slug' => $this->slug,
            'description' => $this->description,
            'address' => $this->address,
            'status' => $this->status->value ?? $this->status,
            'municipality' => $this->when(
                $this->relationLoaded('municipality') && $this->municipality !== null,
                fn () => [
                    'id' => $this->municipality->id,
                    'name' => $this->municipality->name,
                    'slug' => $this->municipality->slug,
                ],
            ),
        ];
    }
}
