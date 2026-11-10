<?php

namespace App\Domains\Posts\Services;

use App\Domains\Posts\Exceptions\PostDomainException;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostReaction;
use App\Domains\Posts\Support\PostMembershipGuard;
use App\Models\User;

class ReactToPostService
{
    public function __construct(private readonly PostMembershipGuard $guard) {}

    public function execute(Post $post, User $user, string $type = 'like'): PostReaction
    {
        if (! $post->allowsEngagement()) {
            throw new PostDomainException('No se permiten reacciones en esta publicación.');
        }

        if ($post->isCommunity()) {
            $post->loadMissing('neighborhoodGroup');
            $this->guard->assertGroupAllowsPosting($post->neighborhoodGroup);
            $this->guard->assertActiveGroupMember($user, $post->neighborhoodGroup);
        }

        return PostReaction::query()->updateOrCreate(
            ['post_id' => $post->id, 'user_id' => $user->id],
            [
                'municipality_id' => $post->municipality_id,
                'type' => $type,
            ],
        );
    }

    public function remove(Post $post, User $user): void
    {
        PostReaction::query()
            ->where('post_id', $post->id)
            ->where('user_id', $user->id)
            ->delete();
    }
}
