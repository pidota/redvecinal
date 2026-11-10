<?php

namespace App\Domains\Posts\Services;

use App\Domains\Posts\Enums\PostRevisionStatus;
use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Exceptions\PostDomainException;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostRevision;
use App\Models\User;
use Illuminate\Support\Facades\DB;

class UpdatePostRevisionService
{
    public function execute(
        Post $post,
        User $actor,
        int $categoryId,
        string $title,
        string $body,
    ): PostRevision {
        if ($post->author_id !== $actor->id) {
            throw new PostDomainException('Solo el autor puede editar la publicación.');
        }

        return DB::transaction(function () use ($post, $actor, $categoryId, $title, $body) {
            $post = Post::query()->whereKey($post->id)->lockForUpdate()->firstOrFail();

            if ($post->pendingRevision()->exists()) {
                throw new PostDomainException('Ya existe una revisión pendiente de aprobación.');
            }

            return match ($post->status) {
                PostStatus::Draft, PostStatus::Rejected => $this->updateWorkingRevision($post, $categoryId, $title, $body),
                PostStatus::Published => $this->createAmendmentRevision($post, $actor, $categoryId, $title, $body),
                default => throw new PostDomainException('No se puede editar la publicación en su estado actual.'),
            };
        });
    }

    private function updateWorkingRevision(Post $post, int $categoryId, string $title, string $body): PostRevision
    {
        $revision = $post->revisions()
            ->whereIn('status', [PostRevisionStatus::Draft, PostRevisionStatus::Rejected])
            ->latest('revision_number')
            ->first();

        if (! $revision) {
            throw new PostDomainException('No se encontró una revisión editable.');
        }

        $revision->update([
            'category_id' => $categoryId,
            'title' => $title,
            'body' => $body,
            'status' => PostRevisionStatus::Draft,
            'rejection_reason' => null,
        ]);

        $post->update(['category_id' => $categoryId]);

        return $revision->fresh();
    }

    private function createAmendmentRevision(Post $post, User $actor, int $categoryId, string $title, string $body): PostRevision
    {
        $current = $post->currentPublishedRevision;
        if (! $current) {
            throw new PostDomainException('La publicación no tiene una revisión publicada.');
        }

        $hasOpenAmendment = $post->revisions()
            ->where('revision_number', '>', $current->revision_number)
            ->whereIn('status', [PostRevisionStatus::Draft, PostRevisionStatus::Pending])
            ->exists();

        if ($hasOpenAmendment) {
            throw new PostDomainException('Ya existe una enmienda abierta para esta publicación.');
        }

        $nextNumber = (int) $post->revisions()->max('revision_number') + 1;

        return PostRevision::query()->create([
            'post_id' => $post->id,
            'municipality_id' => $post->municipality_id,
            'revision_number' => $nextNumber,
            'category_id' => $categoryId,
            'title' => $title,
            'body' => $body,
            'status' => PostRevisionStatus::Draft,
            'created_by' => $actor->id,
        ]);
    }
}
