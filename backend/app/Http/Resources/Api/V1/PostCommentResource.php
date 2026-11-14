<?php

namespace App\Http\Resources\Api\V1;

use App\Domains\Posts\Models\PostComment;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin PostComment */
class PostCommentResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'post_id' => $this->post_id,
            'municipality_id' => $this->municipality_id,
            'author_id' => $this->author_id,
            'author' => $this->when(
                $this->relationLoaded('author') && $this->author !== null,
                fn () => PostAuthorResource::make($this->author),
            ),
            'body' => $this->body,
            'status' => $this->status->value,
            'created_at' => $this->created_at?->toIso8601String(),
            'updated_at' => $this->updated_at?->toIso8601String(),
        ];
    }
}