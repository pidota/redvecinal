<?php

namespace App\Domains\Posts\Support;

use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostModerationEvent;
use App\Models\User;

class PostModerationEventRecorder
{
    public function record(
        Post $post,
        string $event,
        ?User $actor = null,
        ?string $fromStatus = null,
        ?string $toStatus = null,
        array $payload = [],
    ): PostModerationEvent {
        return PostModerationEvent::query()->create([
            'post_id' => $post->id,
            'municipality_id' => $post->municipality_id,
            'actor_user_id' => $actor?->id,
            'event' => $event,
            'from_status' => $fromStatus,
            'to_status' => $toStatus,
            'payload' => $payload,
            'created_at' => now(),
        ]);
    }
}
