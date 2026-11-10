<?php

namespace App\Domains\Posts\Services;

use App\Domains\Municipality\Models\Municipality;
use App\Domains\Posts\Enums\PostRevisionStatus;
use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Enums\PostVisibility;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostRevision;
use App\Domains\Posts\Support\PostModerationEventRecorder;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;

class PublishOfficialPostService
{
    public function __construct(private readonly PostModerationEventRecorder $recorder) {}

    public function execute(
        Municipality $municipality,
        User $author,
        int $categoryId,
        string $title,
        string $body,
        bool $commentsEnabled = true,
    ): Post {
        Gate::forUser($author)->authorize('createMunicipal', [Post::class, $municipality->id]);

        return DB::transaction(function () use ($municipality, $author, $categoryId, $title, $body, $commentsEnabled) {
            $now = now();

            $post = Post::query()->create([
                'municipality_id' => $municipality->id,
                'neighborhood_group_id' => null,
                'author_id' => $author->id,
                'category_id' => $categoryId,
                'status' => PostStatus::Published,
                'visibility' => PostVisibility::MunicipalFeed,
                'published_at' => $now,
                'comments_enabled' => $commentsEnabled,
            ]);

            $revision = PostRevision::query()->create([
                'post_id' => $post->id,
                'municipality_id' => $municipality->id,
                'revision_number' => 1,
                'category_id' => $categoryId,
                'title' => $title,
                'body' => $body,
                'status' => PostRevisionStatus::Approved,
                'created_by' => $author->id,
                'approved_at' => $now,
                'reviewed_at' => $now,
                'reviewed_by' => $author->id,
            ]);

            $post->update(['current_published_revision_id' => $revision->id]);

            $this->recorder->record($post, 'municipal_published', $author, null, PostStatus::Published->value);

            return $post->fresh();
        });
    }
}
