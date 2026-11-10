<?php

namespace App\Domains\Posts\Services;

use App\Domains\Posts\Enums\PostRevisionStatus;
use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Events\PostRevisionApproved;
use App\Domains\Posts\Exceptions\PostDomainException;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostRevision;
use App\Domains\Posts\Support\PostMembershipGuard;
use App\Domains\Posts\Support\PostModerationEventRecorder;
use App\Models\User;
use Illuminate\Support\Facades\DB;

class ApprovePostService
{
    public function __construct(
        private readonly PostMembershipGuard $guard,
        private readonly PostModerationEventRecorder $recorder,
    ) {}

    public function execute(Post $post, User $reviewer, ?PostRevision $revision = null): Post
    {
        $post->loadMissing('neighborhoodGroup');
        $this->guard->assertCanModerateGroup($reviewer, $post->neighborhoodGroup);
        $this->guard->assertNotSelfModeration($reviewer, $post);

        return DB::transaction(function () use ($post, $reviewer, $revision) {
            $post = Post::query()->whereKey($post->id)->lockForUpdate()->firstOrFail();

            $target = $revision ?? $post->pendingRevision()->first();
            if (! $target || $target->status !== PostRevisionStatus::Pending) {
                throw new PostDomainException('No hay una revisión pendiente para aprobar.');
            }

            $isAmendment = $post->status === PostStatus::Published && $post->current_published_revision_id !== null;

            $previousPublishedId = $post->current_published_revision_id;

            if ($previousPublishedId && $previousPublishedId !== $target->id) {
                PostRevision::query()->whereKey($previousPublishedId)->update([
                    'status' => PostRevisionStatus::Superseded,
                ]);
            }

            $now = now();
            $target->update([
                'status' => PostRevisionStatus::Approved,
                'reviewed_by' => $reviewer->id,
                'reviewed_at' => $now,
                'approved_at' => $now,
            ]);

            $post->update([
                'status' => PostStatus::Published,
                'category_id' => $target->category_id,
                'current_published_revision_id' => $target->id,
                'published_at' => $post->published_at ?? $now,
            ]);

            $this->recorder->record(
                $post,
                $isAmendment ? 'amendment_approved' : 'approved',
                $reviewer,
                $isAmendment ? PostStatus::Published->value : PostStatus::Pending->value,
                PostStatus::Published->value,
                ['revision_id' => $target->id],
            );

            event(new PostRevisionApproved($post, $target, $reviewer, $isAmendment));

            return $post->fresh();
        });
    }
}
