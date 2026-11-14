<?php

namespace App\Http\Controllers\Api\V1;

use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostCategory;
use App\Http\Controllers\Controller;
use App\Http\Resources\Api\V1\PostCategoryResource;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class PostCategoryController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        $this->authorize('viewAny', Post::class);

        $user = $request->user();
        $query = PostCategory::query()->where('is_active', true);

        if (! $user->isSuperAdmin()) {
            $municipalityIds = $user->groupMemberships()
                ->where('status', 'active')
                ->pluck('municipality_id')
                ->unique();

            $query->where(function ($builder) use ($municipalityIds) {
                $builder->where('catalog_scope', 'global')
                    ->orWhereIn('municipality_id', $municipalityIds);
            });
        }

        if ($request->filled('audience')) {
            $query->where('default_audience', $request->string('audience'));
        }

        $categories = $query
            ->orderBy('sort_order')
            ->orderBy('name')
            ->get();

        return PostCategoryResource::collection($categories);
    }
}