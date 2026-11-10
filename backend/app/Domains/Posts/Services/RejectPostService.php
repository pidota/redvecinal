<?php

namespace App\Domains\Posts\Services;

use App\Domains\Posts\Enums\PostRevisionStatus;
use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Events\PostRevisionRejected;
use App\Domains\Posts\Exceptions\PostDomainException;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostRevision;
use App\Domains\Posts\Support\PostMembershipGuard;
use App\Domains\Posts\Support\PostModerationEventRecorder;
use App\Models\User;
use Illuminate\Support\Facades\DB;

class RejectPostService
{
    public function __construct(
        private readonly PostMembershipGuard $guard,
        private readonly PostModerationEventRecorder $recorder,
    ) {}

    public function execute(Post $post, User $reviewer, string $reason, ?PostRevision $revision = null): Post
    {
        $post->loadMissing('neighborhoodGroup');
        $this->guard->assertCanModerateGroup($reviewer, $post->neighborhoodGroup);
        $this->guard->assertNotSelfModeration($reviewer, $post);

        return DB::transaction(function () use ($post, $reviewer, $reason, $revision) {
            $post = Post::query()->whereKey($post->id)->lockForUpdate()->firstOrFail();

            $target = $revision ?? $post->pendingRevision()->first();
            if (! $target || $target->status !== PostRevisionStatus::Pending) {
                throw new PostDomainException('No hay una revisión pendiente para rechazar.');
            }

            $isAmendment = $post->status === PostStatus::Published;

            $target->update([
                'status' => PostRevisionStatus::Rejected,
                'reviewed_by' => $reviewer->id,
                'reviewed_at' => now(),
                'rejection_reason' => $reason,
            ]);

            if (! $isAmendment) {
                $post->update(['status' => PostStatus::Rejected]);
            }

            $this->recorder->record(
                $post,
                $isAmendment ? 'amendment_rejected' : 'rejected',
                $reviewer,
                $isAmendment ? PostStatus::Published->value : PostStatus::Pending->value,
                $isAmendment ? PostStatus::Published->value : PostStatus::Rejected->value,
                ['revision_id' => $target->id],
            );

            event(new PostRevisionRejected($post, $target, $reviewer, $isAmendment));

            return $post->fresh();
        });
    }
}
