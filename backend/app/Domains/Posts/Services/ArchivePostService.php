<?php

namespace App\Domains\Posts\Services;

use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Exceptions\PostDomainException;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Support\PostModerationEventRecorder;
use App\Models\User;

class ArchivePostService
{
    public function __construct(private readonly PostModerationEventRecorder $recorder) {}

    public function execute(Post $post, User $actor): Post
    {
        if ($post->status === PostStatus::Archived) {
            throw new PostDomainException('La publicación ya está archivada.');
        }

        $from = $post->status->value;
        $post->update([
            'status' => PostStatus::Archived,
            'archived_at' => now(),
        ]);

        $this->recorder->record($post, 'archived', $actor, $from, PostStatus::Archived->value);

        return $post->fresh();
    }
}
