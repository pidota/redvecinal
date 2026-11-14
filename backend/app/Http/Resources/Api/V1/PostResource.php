<?php

namespace App\Http\Resources\Api\V1;

use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostRevision;
use App\Domains\Posts\Support\MarkdownRenderer;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Facades\Gate;

/** @mixin Post */
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

        $myReaction = null;
        if ($user && $this->relationLoaded('reactions')) {
            $reaction = $this->reactions->first();
            if ($reaction !== null) {
                $myReaction = ['type' => $reaction->type];
            }
        }

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
            'post_kind' => $this->isCommunity() ? 'community' : 'municipal',
            'author' => $this->when(
                $this->relationLoaded('author') && $this->author !== null,
                fn () => (new PostAuthorResource($this->author))->resolve(),
            ),
            'neighborhood_group' => $this->isCommunity()
                && $this->relationLoaded('neighborhoodGroup')
                && $this->neighborhoodGroup !== null
                ? [
                    'id' => $this->neighborhoodGroup->id,
                    'name' => $this->neighborhoodGroup->name,
                    'slug' => $this->neighborhoodGroup->slug,
                ]
                : null,
            'category' => $this->when(
                $this->relationLoaded('category') && $this->category !== null,
                fn () => [
                    'id' => $this->category->id,
                    'slug' => $this->category->slug,
                    'name' => $this->category->name,
                ],
            ),
            'municipality' => $this->when(
                $this->relationLoaded('municipality') && $this->municipality !== null,
                fn () => [
                    'id' => $this->municipality->id,
                    'name' => $this->municipality->name,
                    'slug' => $this->municipality->slug,
                ],
            ),
            'engagement' => [
                'comments_count' => (int) ($this->comments_count ?? 0),
                'reactions_count' => (int) ($this->reactions_count ?? 0),
                'my_reaction' => $myReaction,
            ],
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
            'attachments' => $this->serializeAttachmentsForRevision(
                $this->resolveContentRevision($published),
                $request,
            ),
            'pending_attachments' => $canSeePending
                ? $this->serializeAttachmentsForRevision($pending, $request)
                : [],
        ];
    }

    private function resolveContentRevision(?PostRevision $published): ?PostRevision
    {
        if ($published !== null) {
            return $published;
        }

        if (! $this->relationLoaded('revisions')) {
            return null;
        }

        return $this->revisions->first();
    }

    /**
     * @return array<int, array<string, mixed>>
     */
    private function serializeAttachmentsForRevision(?PostRevision $revision, Request $request): array
    {
        if ($revision === null || ! $revision->relationLoaded('attachments')) {
            return [];
        }

        $user = $request->user();
        if ($user === null) {
            return [];
        }

        if (! $this->mayExposeAttachmentsForRevision($revision, $user)) {
            return [];
        }

        return $revision->attachments
            ->map(fn ($attachment) => (new PostAttachmentResource($attachment))->resolve())
            ->values()
            ->all();
    }

    private function mayExposeAttachmentsForRevision(PostRevision $revision, $user): bool
    {
        /** @var Post $post */
        $post = $this->resource;

        if (
            $post->current_published_revision_id === $revision->id
            && in_array($post->status, [PostStatus::Published, PostStatus::Hidden], true)
        ) {
            return Gate::forUser($user)->allows('view', $post);
        }

        return Gate::forUser($user)->allows('viewAttachment', [$post, $revision->id]);
    }
}