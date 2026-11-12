<?php

namespace App\Http\Resources\Api\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class MembershipRequestResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'status' => $this->status->value ?? $this->status,
            'neighborhood_group_id' => $this->neighborhood_group_id,
            'request_note' => $this->request_note,
            'review_note' => $this->when(
                $this->shouldExposeReview($request),
                $this->review_note
            ),
            'reviewed_at' => $this->reviewed_at?->toIso8601String(),
            'rejected_at' => $this->rejected_at?->toIso8601String(),
            'cancelled_at' => $this->cancelled_at?->toIso8601String(),
            'created_at' => $this->created_at?->toIso8601String(),
            'neighborhood_group' => $this->when(
                $this->relationLoaded('neighborhoodGroup') && $this->neighborhoodGroup !== null,
                fn () => new NeighborhoodGroupResource($this->neighborhoodGroup),
            ),
            'requester' => $this->when(
                $this->shouldExposeRequester($request) && $this->relationLoaded('user'),
                fn () => [
                    'id' => $this->user_id,
                    'name' => $this->user?->name,
                ],
            ),
        ];
    }

    private function shouldExposeRequester(Request $request): bool
    {
        $user = $request->user();
        if ($user === null) {
            return false;
        }

        if ($this->user_id === $user->id) {
            return false;
        }

        return $request->user()?->can('view', $this->resource) ?? false;
    }

    private function shouldExposeReview(Request $request): bool
    {
        return $this->review_note !== null
            && ($request->user()?->can('view', $this->resource) ?? false);
    }
}
