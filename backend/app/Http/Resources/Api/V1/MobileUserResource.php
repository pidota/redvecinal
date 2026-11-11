<?php

namespace App\Http\Resources\Api\V1;

use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin User */
class MobileUserResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $memberships = $this->activeMunicipalityMemberships()
            ->with('municipality:id,name,slug')
            ->get();

        return [
            'id' => $this->id,
            'name' => $this->name,
            'email' => $this->email,
            'municipality_memberships' => $memberships->map(fn ($member) => [
                'id' => $member->id,
                'municipality_id' => $member->municipality_id,
                'municipality' => $member->municipality ? [
                    'id' => $member->municipality->id,
                    'name' => $member->municipality->name,
                    'slug' => $member->municipality->slug,
                ] : null,
                'role' => $member->role->value,
                'status' => $member->status->value,
            ])->values()->all(),
        ];
    }
}
