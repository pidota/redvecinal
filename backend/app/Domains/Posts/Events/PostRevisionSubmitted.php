<?php

namespace App\Domains\Posts\Events;

use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostRevision;
use App\Models\User;
use Illuminate\Foundation\Events\Dispatchable;
use Illuminate\Queue\SerializesModels;

class PostRevisionSubmitted
{
    use Dispatchable, SerializesModels;

    public function __construct(
        public Post $post,
        public PostRevision $revision,
        public User $actor,
    ) {}
}
