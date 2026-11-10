<?php

namespace App\Domains\Posts\Policies;

use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Models\Post;
use App\Models\User;

class PostPolicy
{
    public function viewAny(User $user): bool
    {
        return $user->groupMemberships()->where('status', MembershipStatus::Active)->exists()
            || $user->isSuperAdmin()
            || $user->activeMunicipalityMemberships()->exists();
    }

    public function view(User $user, Post $post): bool
    {
        return match ($post->status) {
            PostStatus::Published, PostStatus::Hidden => $this->canViewPublishedScope($user, $post),
            PostStatus::Draft, PostStatus::Rejected => $post->author_id === $user->id,
            PostStatus::Pending => $post->author_id === $user->id || $this->canModerateCommunity($user, $post),
            PostStatus::Archived => $post->author_id === $user->id
                || $this->canModerateCommunity($user, $post)
                || $this->isMunicipalOperator($user, $post->municipality_id),
            default => false,
        };
    }

    public function create(User $user): bool
    {
        return $user->groupMemberships()->where('status', MembershipStatus::Active)->exists();
    }

    public function createInGroup(User $user, int $neighborhoodGroupId): bool
    {
        return $user->groupMemberships()
            ->where('neighborhood_group_id', $neighborhoodGroupId)
            ->where('status', MembershipStatus::Active)
            ->exists();
    }

    public function update(User $user, Post $post): bool
    {
        if ($post->author_id !== $user->id) {
            return false;
        }

        return in_array($post->status, [PostStatus::Draft, PostStatus::Rejected, PostStatus::Published], true)
            && $post->isCommunity();
    }

    public function submit(User $user, Post $post): bool
    {
        return $post->author_id === $user->id
            && $post->isCommunity()
            && in_array($post->status, [PostStatus::Draft, PostStatus::Rejected, PostStatus::Published], true)
            && $this->hasActiveMembershipInPostGroup($user, $post);
    }

    public function approve(User $user, Post $post): bool
    {
        if (! $post->isCommunity() || $post->author_id === $user->id) {
            return false;
        }

        return $this->canModerateCommunity($user, $post);
    }

    public function reject(User $user, Post $post): bool
    {
        return $this->approve($user, $post);
    }

    public function publishDirect(User $user, Post $post): bool
    {
        if (! $post->isCommunity() || $post->author_id !== $user->id) {
            return false;
        }

        $membership = $user->activeGroupMembershipFor($post->neighborhoodGroup);

        return $membership?->canPerformGroupAdministration() === true;
    }

    public function hide(User $user, Post $post): bool
    {
        if ($this->isMunicipalOperator($user, $post->municipality_id)) {
            return $user->can('posts.community.hide') || $user->can('posts.municipal.hide');
        }

        return $this->canModerateCommunity($user, $post);
    }

    public function restore(User $user, Post $post): bool
    {
        return $this->hide($user, $post) && $post->status === PostStatus::Hidden;
    }

    public function archive(User $user, Post $post): bool
    {
        if ($post->author_id === $user->id && in_array($post->status, [PostStatus::Draft, PostStatus::Rejected], true)) {
            return true;
        }

        return $this->canModerateCommunity($user, $post)
            || $this->isMunicipalOperator($user, $post->municipality_id);
    }

    public function comment(User $user, Post $post): bool
    {
        if (! $post->allowsEngagement() || ! $post->comments_enabled) {
            return false;
        }

        if ($post->isCommunity() && ! $post->neighborhoodGroup?->isAdministrable()) {
            return false;
        }

        return $this->canViewPublishedScope($user, $post)
            && $this->hasActiveMembershipInPostGroup($user, $post);
    }

    public function react(User $user, Post $post): bool
    {
        return $this->comment($user, $post);
    }

    public function report(User $user, Post $post): bool
    {
        return $this->view($user, $post) && $post->status === PostStatus::Published;
    }

    public function viewPendingQueue(User $user, Post $post): bool
    {
        return $this->canModerateCommunity($user, $post);
    }

    public function createMunicipal(User $user, int $municipalityId): bool
    {
        if ($user->isSuperAdmin()) {
            return true;
        }

        return $user->isMunicipalAdministratorFor($municipalityId)
            && $user->can('posts.municipal.create');
    }

    public function viewAttachment(User $user, Post $post, int $revisionId): bool
    {
        $revision = $post->revisions()->whereKey($revisionId)->first();
        if (! $revision) {
            return false;
        }

        if ($post->current_published_revision_id === $revision->id && $this->canViewPublishedScope($user, $post)) {
            return true;
        }

        if ($revision->status->value === 'pending' && $this->view($user, $post)) {
            return $post->author_id === $user->id || $this->canModerateCommunity($user, $post);
        }

        return $post->author_id === $user->id && in_array($post->status, [PostStatus::Draft, PostStatus::Rejected], true);
    }

    private function canViewPublishedScope(User $user, Post $post): bool
    {
        if ($user->isSuperAdmin()) {
            return true;
        }

        if ($post->isMunicipal()) {
            if ($this->isMunicipalOperator($user, $post->municipality_id)) {
                return true;
            }

            return $user->groupMemberships()
                ->where('municipality_id', $post->municipality_id)
                ->where('status', MembershipStatus::Active)
                ->exists();
        }

        return $this->hasActiveMembershipInPostGroup($user, $post);
    }

    private function canModerateCommunity(User $user, Post $post): bool
    {
        if (! $post->isCommunity()) {
            return false;
        }

        $group = $post->neighborhoodGroup;
        if (! $group?->isAdministrable()) {
            return false;
        }

        $membership = $user->activeGroupMembershipFor($group);

        return $membership?->canPerformGroupAdministration() === true;
    }

    private function hasActiveMembershipInPostGroup(User $user, Post $post): bool
    {
        if ($post->isMunicipal()) {
            return $user->groupMemberships()
                ->where('municipality_id', $post->municipality_id)
                ->where('status', MembershipStatus::Active)
                ->exists();
        }

        return $user->groupMemberships()
            ->where('neighborhood_group_id', $post->neighborhood_group_id)
            ->where('status', MembershipStatus::Active)
            ->exists();
    }

    private function isMunicipalOperator(User $user, int $municipalityId): bool
    {
        if ($user->isSuperAdmin()) {
            return true;
        }

        return $user->isMunicipalAdministratorFor($municipalityId);
    }
}
