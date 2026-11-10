<?php

namespace App\Domains\Posts\Policies;

use App\Domains\Posts\Models\PostComment;
use App\Models\User;

class PostCommentPolicy
{
    public function viewAny(User $user, PostComment $comment): bool
    {
        return app(PostPolicy::class)->view($user, $comment->post);
    }
}
