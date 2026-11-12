<?php

namespace App\Http\Controllers\Api\V1;

use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Support\ReviewableNeighborhoodGroupsQuery;
use App\Http\Controllers\Controller;
use App\Http\Resources\Api\V1\GroupMemberResource;
use App\Http\Resources\Api\V1\NeighborhoodGroupResource;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class NeighborhoodGroupController extends Controller
{
    public function index(Request $request): AnonymousResourceCollection
    {
        $this->authorize('viewAny', NeighborhoodGroup::class);

        $query = NeighborhoodGroup::query()->with('municipality');

        $user = $request->user();
        if (! $user->isSuperAdmin()) {
            $municipalityIds = $user->activeMunicipalityMemberships()->pluck('municipality_id')
                ->merge($user->groupMemberships()->where('status', 'active')->pluck('municipality_id'))
                ->unique();
            $query->whereIn('municipality_id', $municipalityIds);
        }

        $groups = $query->orderBy('name')->paginate();

        return NeighborhoodGroupResource::collection($groups);
    }

    public function show(Request $request, NeighborhoodGroup $group): NeighborhoodGroupResource
    {
        $this->authorize('view', $group);

        $group->load('municipality');

        return new NeighborhoodGroupResource($group);
    }

    public function reviewableGroups(Request $request): AnonymousResourceCollection
    {
        $groups = ReviewableNeighborhoodGroupsQuery::forUser($request->user())
            ->with('municipality')
            ->orderBy('name')
            ->orderBy('id')
            ->paginate();

        return NeighborhoodGroupResource::collection($groups);
    }

    public function myGroups(Request $request): AnonymousResourceCollection
    {
        $groups = NeighborhoodGroup::query()
            ->whereHas('memberships', function ($query) use ($request) {
                $query->where('user_id', $request->user()->id)
                    ->where('status', 'active');
            })
            ->with('municipality')
            ->orderBy('name')
            ->get();

        return NeighborhoodGroupResource::collection($groups);
    }

    public function members(Request $request, NeighborhoodGroup $group): AnonymousResourceCollection
    {
        $this->authorize('view', $group);

        $members = $group->memberships()
            ->with('user')
            ->where('status', 'active')
            ->get();

        return GroupMemberResource::collection($members);
    }
}
