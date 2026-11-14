<?php

namespace App\Http\Controllers\Api\V1;

use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostRevision;
use App\Domains\Posts\Services\ApprovePostService;
use App\Domains\Posts\Services\ArchivePostService;
use App\Domains\Posts\Services\CreateCommunityPostService;
use App\Domains\Posts\Services\HidePostService;
use App\Domains\Posts\Services\PublishCommunityPostDirectService;
use App\Domains\Posts\Services\RejectPostService;
use App\Domains\Posts\Services\RestorePostService;
use App\Domains\Posts\Services\SubmitPostService;
use App\Domains\Posts\Services\UpdatePostRevisionService;
use App\Http\Controllers\Controller;
use App\Http\Resources\Api\V1\PostResource;
use App\Http\Support\EagerLoadsPostsForApi;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Gate;

class PostController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        $this->authorize('viewAny', Post::class);

        $user = $request->user();
        $query = Post::query()
            ->where('status', PostStatus::Published);
        EagerLoadsPostsForApi::applyToQuery($query, $user);

        if (! $user->isSuperAdmin()) {
            $municipalityIds = $user->groupMemberships()->where('status', 'active')->pluck('municipality_id')->unique();
            $groupIds = $user->groupMemberships()->where('status', 'active')->pluck('neighborhood_group_id')->unique();

            $query->where(function ($builder) use ($municipalityIds, $groupIds) {
                $builder->where(function ($municipal) use ($municipalityIds) {
                    $municipal->whereNull('neighborhood_group_id')
                        ->whereIn('municipality_id', $municipalityIds);
                })->orWhereIn('neighborhood_group_id', $groupIds);
            });
        }

        if ($request->filled('neighborhood_group_id')) {
            $query->where('neighborhood_group_id', $request->integer('neighborhood_group_id'));
        }

        if ($request->filled('municipality_id')) {
            $query->where('municipality_id', $request->integer('municipality_id'));
        }

        return PostResource::collection($query->orderByDesc('published_at')->paginate());
    }

    public function show(Request $request, Post $post): PostResource
    {
        if (! Gate::forUser($request->user())->allows('view', $post)) {
            abort(404);
        }

        EagerLoadsPostsForApi::loadOntoModel($post, $request->user());

        return new PostResource($post);
    }

    public function store(Request $request, CreateCommunityPostService $create): PostResource|JsonResponse
    {
        $this->authorize('create', Post::class);

        $data = $request->validate([
            'neighborhood_group_id' => ['required', 'integer', 'exists:neighborhood_groups,id'],
            'category_id' => ['required', 'integer', 'exists:post_categories,id'],
            'title' => ['required', 'string', 'max:200'],
            'body' => ['required', 'string', 'max:50000'],
            'publish_direct' => ['sometimes', 'boolean'],
        ]);

        $group = NeighborhoodGroup::query()->findOrFail($data['neighborhood_group_id']);
        if (! Gate::forUser($request->user())->allows('createInGroup', [Post::class, $group->id])) {
            abort(403);
        }

        if ($request->boolean('publish_direct')) {
            $post = app(PublishCommunityPostDirectService::class)->execute(
                $group,
                $request->user(),
                $data['category_id'],
                $data['title'],
                $data['body'],
            );
        } else {
            $post = $create->execute(
                $group,
                $request->user(),
                $data['category_id'],
                $data['title'],
                $data['body'],
            );
        }

        EagerLoadsPostsForApi::loadOntoModel($post, $request->user());

        return new PostResource($post);
    }

    public function update(Request $request, Post $post, UpdatePostRevisionService $update): PostResource
    {
        $this->authorize('update', $post);

        $data = $request->validate([
            'category_id' => ['required', 'integer', 'exists:post_categories,id'],
            'title' => ['required', 'string', 'max:200'],
            'body' => ['required', 'string', 'max:50000'],
        ]);

        $update->execute($post, $request->user(), $data['category_id'], $data['title'], $data['body']);
        $post->refresh();
        EagerLoadsPostsForApi::loadOntoModel($post, $request->user());

        return new PostResource($post);
    }

    public function submit(Request $request, Post $post, SubmitPostService $submit): PostResource
    {
        $this->authorize('submit', $post);
        $submit->execute($post, $request->user());
        $post->refresh();
        EagerLoadsPostsForApi::loadOntoModel($post, $request->user());

        return new PostResource($post);
    }

    public function approve(Request $request, Post $post, ApprovePostService $approve): PostResource
    {
        $this->authorize('approve', $post);
        $approve->execute($post, $request->user());
        $post->refresh();
        EagerLoadsPostsForApi::loadOntoModel($post, $request->user());

        return new PostResource($post);
    }

    public function reject(Request $request, Post $post, RejectPostService $reject): PostResource
    {
        $this->authorize('reject', $post);

        $data = $request->validate([
            'rejection_reason' => ['required', 'string', 'max:2000'],
        ]);

        $reject->execute($post, $request->user(), $data['rejection_reason']);
        $post->refresh();
        EagerLoadsPostsForApi::loadOntoModel($post, $request->user());

        return new PostResource($post);
    }

    public function hide(Request $request, Post $post, HidePostService $hide): PostResource
    {
        $this->authorize('hide', $post);
        $data = $request->validate(['reason' => ['nullable', 'string', 'max:500']]);
        $hide->execute($post, $request->user(), $data['reason'] ?? null);
        $post->refresh();
        EagerLoadsPostsForApi::loadOntoModel($post, $request->user());

        return new PostResource($post);
    }

    public function restore(Request $request, Post $post, RestorePostService $restore): PostResource
    {
        $this->authorize('restore', $post);
        $restore->execute($post, $request->user());
        $post->refresh();
        EagerLoadsPostsForApi::loadOntoModel($post, $request->user());

        return new PostResource($post);
    }

    public function archive(Request $request, Post $post, ArchivePostService $archive): PostResource
    {
        $this->authorize('archive', $post);
        $archive->execute($post, $request->user());
        $post->refresh();
        EagerLoadsPostsForApi::loadOntoModel($post, $request->user());

        return new PostResource($post);
    }

    public function mine(Request $request): AnonymousResourceCollection
    {
        $user = $request->user();
        $query = Post::query()
            ->where('author_id', $user->id)
            ->orderByDesc('updated_at');
        EagerLoadsPostsForApi::applyToQuery($query, $user);
        $posts = $query->paginate();

        return PostResource::collection($posts);
    }

    public function pendingForGroup(Request $request, NeighborhoodGroup $group): AnonymousResourceCollection
    {
        if (! $group->isAdministrable()) {
            abort(404);
        }

        $user = $request->user();
        $sample = Post::query()->make([
            'municipality_id' => $group->municipality_id,
            'neighborhood_group_id' => $group->id,
            'author_id' => 0,
            'category_id' => 1,
        ]);
        $sample->setRelation('neighborhoodGroup', $group);

        if (! Gate::forUser($user)->allows('viewPendingQueue', $sample)) {
            abort(403);
        }

        $query = Post::query()
            ->where('neighborhood_group_id', $group->id);
        EagerLoadsPostsForApi::applyToQuery($query, $user);
        $posts = $query
            ->where(function ($query) {
                $query->where('status', PostStatus::Pending)
                    ->orWhereHas('pendingRevision');
            })
            ->orderBy('submitted_at')
            ->paginate();

        return PostResource::collection($posts);
    }
}
