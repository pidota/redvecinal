<?php

namespace App\Http\Resources\Api\V1;

use App\Domains\Posts\Support\MarkdownRenderer;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class PostResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $renderer = app(MarkdownRenderer::class);
        $published = $this->currentPublishedRevision;
        $pending = $this->relationLoaded('pendingRevision') ? $this->pendingRevision : null;
        $user = $request->user();
        $canSeePending = $pending && $user && (
            $user->id === $this->author_id
            || $user->can('approve', $this->resource)
        );

        return [
            'id' => $this->id,
            'municipality_id' => $this->municipality_id,
            'neighborhood_group_id' => $this->neighborhood_group_id,
            'author_id' => $this->author_id,
            'category_id' => $this->category_id,
            'status' => $this->status->value,
            'visibility' => $this->visibility->value,
            'comments_enabled' => $this->comments_enabled,
            'published_at' => $this->published_at?->toIso8601String(),
            'has_pending_amendment' => $pending !== null,
            'content' => $published ? [
                'revision_id' => $published->id,
                'title' => $published->title,
                'body' => $published->body,
                'body_html' => $renderer->toSafeHtml($published->body),
                'category_id' => $published->category_id,
            ] : null,
            'pending_content' => $canSeePending ? [
                'revision_id' => $pending->id,
                'title' => $pending->title,
                'body' => $pending->body,
                'body_html' => $renderer->toSafeHtml($pending->body),
            ] : null,
        ];
    }
}
