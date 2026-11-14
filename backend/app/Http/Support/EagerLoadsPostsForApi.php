<?php

namespace App\Http\Support;

use App\Domains\Posts\Enums\PostCommentStatus;
use App\Domains\Posts\Enums\PostRevisionStatus;
use App\Domains\Posts\Models\Post;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;

final class EagerLoadsPostsForApi
{
    public static function applyToQuery(Builder $query, User $user): Builder
    {
        return $query
            ->with(self::withRelations($user))
            ->withCount(self::withCounts());
    }

    /**
     * @return array<int|string, mixed>
     */
    public static function withRelations(User $user): array
    {
        $userId = $user->id;

        return [
            'author:id,name',
            'category:id,slug,name',
            'municipality:id,name,slug',
            'neighborhoodGroup:id,name,slug,municipality_id',
            'currentPublishedRevision.attachments',
            'pendingRevision.attachments',
            'revisions' => static function ($query): void {
                $query
                    ->whereIn('status', [
                        PostRevisionStatus::Draft,
                        PostRevisionStatus::Pending,
                        PostRevisionStatus::Rejected,
                    ])
                    ->with('attachments')
                    ->orderByDesc('id');
            },
            'reactions' => static function ($query) use ($userId): void {
                $query
                    ->where('user_id', $userId)
                    ->select(['id', 'post_id', 'user_id', 'type']);
            },
        ];
    }

    /**
     * @return array<int|string, mixed>
     */
    public static function withCounts(): array
    {
        return [
            'comments as comments_count' => static function ($query): void {
                $query->where('status', PostCommentStatus::Visible->value);
            },
            'reactions as reactions_count',
        ];
    }

    public static function loadOntoModel(Post $post, User $user): Post
    {
        return $post->load(self::withRelations($user))
            ->loadCount(self::withCounts());
    }
}