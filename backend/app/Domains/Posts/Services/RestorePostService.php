<?php

namespace App\Domains\Posts\Services;

use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Exceptions\PostDomainException;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Support\PostModerationEventRecorder;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;

class RestorePostService
{
    public function __construct(private readonly PostModerationEventRecorder $recorder) {}

    public function execute(Post $post, User $actor): Post
    {
        Gate::forUser($actor)->authorize('restore', $post);

        if ($post->status !== PostStatus::Hidden) {
            throw new PostDomainException('La publicación no está oculta.');
        }

        return DB::transaction(function () use ($post, $actor) {
            $post->update([
                'status' => PostStatus::Published,
                'hidden_at' => null,
            ]);

            $this->recorder->record($post, 'restored', $actor, PostStatus::Hidden->value, PostStatus::Published->value);

            return $post->fresh();
        });
    }
}
