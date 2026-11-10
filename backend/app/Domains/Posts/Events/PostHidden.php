<?php

namespace App\Domains\Posts\Events;

use App\Domains\Posts\Models\Post;
use App\Models\User;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class PostHidden
{
    use Dispatchable, SerializesModels;

    public function __construct(
        public Post $post,
        public User $actor,
        public ?string $reason = null,
    ) {}
}
