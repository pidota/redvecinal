<?php

namespace App\Domains\Posts\Services;

use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Events\PostHidden;
use App\Domains\Posts\Exceptions\PostDomainException;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Support\PostModerationEventRecorder;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;

class HidePostService
{
    public function __construct(private readonly PostModerationEventRecorder $recorder) {}

    public function execute(Post $post, User $actor, ?string $reason = null): Post
    {
        Gate::forUser($actor)->authorize('hide', $post);

        if ($post->status !== PostStatus::Published) {
            throw new PostDomainException('Solo se pueden ocultar publicaciones publicadas.');
        }

        $from = $post->status->value;

        $post = DB::transaction(function () use ($post, $actor, $from, $reason) {
            $post->update([
                'status' => PostStatus::Hidden,
                'hidden_at' => now(),
            ]);

            $this->recorder->record($post, 'hidden', $actor, $from, PostStatus::Hidden->value, [
                'reason' => $reason,
            ]);

            return $post->fresh();
        });

        event(new PostHidden($post, $actor, $reason));

        return $post;
    }
}
