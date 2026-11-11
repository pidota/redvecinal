<?php

namespace App\Http\Resources\Api\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class ChatRoomResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'municipality_id' => $this->municipality_id,
            'neighborhood_group_id' => $this->neighborhood_group_id,
            'type' => $this->type->value,
            'status' => $this->status->value,
            'group' => $this->whenLoaded('neighborhoodGroup', fn () => [
                'id' => $this->neighborhoodGroup->id,
                'name' => $this->neighborhoodGroup->name,
                'slug' => $this->neighborhoodGroup->slug,
            ]),
        ];
    }
}
