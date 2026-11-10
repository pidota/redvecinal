<?php

namespace App\Domains\Posts\Services;

use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Posts\Enums\PostRevisionStatus;
use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Enums\PostVisibility;
use App\Domains\Posts\Events\PostPublishedDirectly;
use App\Domains\Posts\Exceptions\PostDomainException;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostRevision;
use App\Domains\Posts\Support\PostMembershipGuard;
use App\Domains\Posts\Support\PostModerationEventRecorder;
use App\Models\User;
use Illuminate\Support\Facades\DB;

class PublishCommunityPostDirectService
{
    public function __construct(
        private readonly PostMembershipGuard $guard,
        private readonly PostModerationEventRecorder $recorder,
    ) {}

    public function execute(
        NeighborhoodGroup $group,
        User $actor,
        int $categoryId,
        string $title,
        string $body,
    ): Post {
        $this->guard->assertGroupAllowsPosting($group);
        $this->guard->assertActiveGroupMember($actor, $group);

        $membership = $actor->activeGroupMembershipFor($group);
        if (! $membership?->canPerformGroupAdministration()) {
            throw new PostDomainException('Solo presidentes o moderadores pueden publicar directamente.');
        }

        return DB::transaction(function () use ($group, $actor, $categoryId, $title, $body) {
            $now = now();

            $post = Post::query()->create([
                'municipality_id' => $group->municipality_id,
                'neighborhood_group_id' => $group->id,
                'author_id' => $actor->id,
                'category_id' => $categoryId,
                'status' => PostStatus::Published,
                'visibility' => PostVisibility::MembersOnly,
                'published_at' => $now,
            ]);

            $revision = PostRevision::query()->create([
                'post_id' => $post->id,
                'municipality_id' => $group->municipality_id,
                'revision_number' => 1,
                'category_id' => $categoryId,
                'title' => $title,
                'body' => $body,
                'status' => PostRevisionStatus::Approved,
                'created_by' => $actor->id,
                'reviewed_by' => $actor->id,
                'reviewed_at' => $now,
                'approved_at' => $now,
                'submitted_at' => $now,
            ]);

            $post->update(['current_published_revision_id' => $revision->id]);

            $this->recorder->record($post, 'published_direct', $actor, null, PostStatus::Published->value, [
                'revision_id' => $revision->id,
            ]);

            event(new PostPublishedDirectly($post, $revision, $actor));

            return $post->fresh();
        });
    }
}
