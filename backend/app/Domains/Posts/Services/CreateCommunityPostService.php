<?php

namespace App\Domains\Posts\Services;

use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Posts\Enums\PostRevisionStatus;
use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Enums\PostVisibility;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostRevision;
use App\Domains\Posts\Support\PostMembershipGuard;
use App\Domains\Posts\Support\PostModerationEventRecorder;
use App\Models\User;
use Illuminate\Support\Facades\DB;

class CreateCommunityPostService
{
    public function __construct(
        private readonly PostMembershipGuard $guard,
        private readonly PostModerationEventRecorder $recorder,
    ) {}

  public function execute(
        NeighborhoodGroup $group,
        User $author,
        int $categoryId,
        string $title,
        string $body,
    ): Post {
        $this->guard->assertGroupAllowsPosting($group);
        $this->guard->assertActiveGroupMember($author, $group);

        return DB::transaction(function () use ($group, $author, $categoryId, $title, $body) {
            $post = Post::query()->create([
                'municipality_id' => $group->municipality_id,
                'neighborhood_group_id' => $group->id,
                'author_id' => $author->id,
                'category_id' => $categoryId,
                'status' => PostStatus::Draft,
                'visibility' => PostVisibility::MembersOnly,
            ]);

            PostRevision::query()->create([
                'post_id' => $post->id,
                'municipality_id' => $group->municipality_id,
                'revision_number' => 1,
                'category_id' => $categoryId,
                'title' => $title,
                'body' => $body,
                'status' => PostRevisionStatus::Draft,
                'created_by' => $author->id,
            ]);

            $this->recorder->record($post, 'created', $author, null, PostStatus::Draft->value);

            return $post->fresh(['revisions']);
        });
    }
}
