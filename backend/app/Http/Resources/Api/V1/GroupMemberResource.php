<?php

namespace App\Http\Resources\Api\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class GroupMemberResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'user' => [
                'id' => $this->user_id,
                'name' => $this->whenLoaded('user', fn () => $this->user->name),
            ],
            'membership_role' => $this->membership_role->value ?? $this->membership_role,
            'status' => $this->status->value ?? $this->status,
            'joined_at' => $this->joined_at?->toIso8601String(),
        ];
    }
}
