<?php

namespace App\Domains\Posts\Services;

use App\Domains\Posts\Enums\PostRevisionStatus;
use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Events\PostRevisionSubmitted;
use App\Domains\Posts\Exceptions\PostDomainException;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostRevision;
use App\Domains\Posts\Support\PostMembershipGuard;
use App\Domains\Posts\Support\PostModerationEventRecorder;
use App\Models\User;
use Illuminate\Support\Facades\DB;

class SubmitPostService
{
    public function __construct(
        private readonly PostMembershipGuard $guard,
        private readonly PostModerationEventRecorder $recorder,
    ) {}

    public function execute(Post $post, User $actor, ?PostRevision $revision = null): PostRevision
    {
        if ($post->author_id !== $actor->id) {
            throw new PostDomainException('Solo el autor puede enviar la publicación.');
        }

        $post->loadMissing('neighborhoodGroup');
        $this->guard->assertGroupAllowsPosting($post->neighborhoodGroup);
        $this->guard->assertActiveGroupMember($actor, $post->neighborhoodGroup);

        return DB::transaction(function () use ($post, $actor, $revision) {
            $post = Post::query()->whereKey($post->id)->lockForUpdate()->firstOrFail();

            $target = $this->resolveRevision($post, $revision);

            $otherPending = $post->revisions()
                ->where('status', PostRevisionStatus::Pending)
                ->where('id', '!=', $target->id)
                ->exists();
            if ($otherPending) {
                throw new PostDomainException('Ya existe una revisión pendiente de aprobación.');
            }

            if (! in_array($target->status, [PostRevisionStatus::Draft, PostRevisionStatus::Rejected], true)) {
                throw new PostDomainException('Solo se pueden enviar revisiones en borrador o rechazadas.');
            }

            $fromPostStatus = $post->status->value;
            $isAmendment = $post->status === PostStatus::Published;

            $target->update([
                'status' => PostRevisionStatus::Pending,
                'submitted_at' => now(),
                'rejection_reason' => null,
            ]);

            if (! $isAmendment) {
                $post->update([
                    'status' => PostStatus::Pending,
                    'submitted_at' => now(),
                ]);
            }

            $this->recorder->record(
                $post,
                $isAmendment ? 'amendment_submitted' : 'submitted',
                $actor,
                $fromPostStatus,
                $isAmendment ? PostStatus::Published->value : PostStatus::Pending->value,
                ['revision_id' => $target->id],
            );

            event(new PostRevisionSubmitted($post, $target, $actor));

            return $target->fresh();
        });
    }

    private function resolveRevision(Post $post, ?PostRevision $revision): PostRevision
    {
        if ($revision !== null) {
            if ($revision->post_id !== $post->id) {
                throw new PostDomainException('La revisión no pertenece a la publicación.');
            }

            return $revision;
        }

        if ($post->status === PostStatus::Published) {
            $draftAmendment = $post->revisions()
                ->where('status', PostRevisionStatus::Draft)
                ->latest('revision_number')
                ->first();
            if (! $draftAmendment) {
                throw new PostDomainException('Debe crear una nueva revisión antes de enviar cambios.');
            }

            return $draftAmendment;
        }

        $working = $post->revisions()
            ->whereIn('status', [PostRevisionStatus::Draft, PostRevisionStatus::Rejected])
            ->latest('revision_number')
            ->first();

        if (! $working) {
            throw new PostDomainException('No hay contenido para enviar.');
        }

        return $working;
    }
}
