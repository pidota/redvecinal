<?php

namespace App\Domains\Posts\Services;

use App\Domains\Posts\Enums\PostCommentStatus;
use App\Domains\Posts\Exceptions\PostDomainException;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostComment;
use App\Domains\Posts\Support\PostMembershipGuard;
use App\Models\User;

class AddCommentService
{
    public function __construct(private readonly PostMembershipGuard $guard) {}

    public function execute(Post $post, User $author, string $body): PostComment
    {
        if (! $post->allowsEngagement()) {
            throw new PostDomainException('No se permiten comentarios en esta publicación.');
        }

        if ($post->isCommunity()) {
            $post->loadMissing('neighborhoodGroup');
            $this->guard->assertGroupAllowsPosting($post->neighborhoodGroup);
            $this->guard->assertActiveGroupMember($author, $post->neighborhoodGroup);
        }

        return PostComment::query()->create([
            'post_id' => $post->id,
            'municipality_id' => $post->municipality_id,
            'author_id' => $author->id,
            'body' => $body,
            'status' => PostCommentStatus::Visible,
        ]);
    }
}
