<?php

namespace App\Http\Controllers\Api\V1;

use App\Domains\Neighborhoods\Enums\MembershipRequestStatus;
use App\Domains\Neighborhoods\Exceptions\MembershipRequestException;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Models\NeighborhoodMembershipRequest;
use App\Domains\Neighborhoods\Services\ApproveMembershipRequestService;
use App\Domains\Neighborhoods\Services\CancelMembershipRequestService;
use App\Domains\Neighborhoods\Services\RejectMembershipRequestService;
use App\Domains\Neighborhoods\Services\SubmitMembershipRequestService;
use App\Http\Controllers\Controller;
use App\Http\Resources\Api\V1\MembershipRequestResource;
use App\Http\Resources\Api\V1\NeighborhoodGroupResource;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Validation\Rule;

class MembershipRequestController extends Controller
{
    public function store(
        Request $request,
        NeighborhoodGroup $group,
        SubmitMembershipRequestService $submit,
    ): MembershipRequestResource|JsonResponse {
        $this->authorize('create', [NeighborhoodMembershipRequest::class, $group]);

        $data = $request->validate([
            'request_note' => ['nullable', 'string', 'max:500'],
        ]);

        try {
            $membershipRequest = $submit->execute($group, $request->user(), $data['request_note'] ?? null);
            $membershipRequest->load('neighborhoodGroup.municipality');

            return (new MembershipRequestResource($membershipRequest))
                ->response()
                ->setStatusCode(201);
        } catch (MembershipRequestException $e) {
            return response()->json(['message' => $e->getMessage()], $e->httpStatus);
        }
    }

    public function myIndex(Request $request): AnonymousResourceCollection
    {
        $validated = $request->validate([
            'neighborhood_group_id' => ['sometimes', 'integer', 'min:1'],
        ]);

        $query = NeighborhoodMembershipRequest::query()
            ->where('user_id', $request->user()->id)
            ->with(['neighborhoodGroup.municipality'])
            ->orderByDesc('created_at');

        if (isset($validated['neighborhood_group_id'])) {
            $query->where('neighborhood_group_id', $validated['neighborhood_group_id']);
        }

        return MembershipRequestResource::collection($query->paginate());
    }

    public function destroy(
        Request $request,
        NeighborhoodMembershipRequest $membershipRequest,
        CancelMembershipRequestService $cancel,
    ): JsonResponse {
        $this->authorize('cancel', $membershipRequest);

        try {
            $cancel->execute($membershipRequest, $request->user());

            return response()->json(null, 204);
        } catch (MembershipRequestException $e) {
            return response()->json(['message' => $e->getMessage()], $e->httpStatus);
        }
    }

    public function indexForGroup(Request $request, NeighborhoodGroup $group): AnonymousResourceCollection|JsonResponse
    {
        $this->authorize('viewAny', [NeighborhoodMembershipRequest::class, $group]);

        $validated = $request->validate([
            'status' => ['sometimes', Rule::enum(MembershipRequestStatus::class)],
        ]);

        $query = NeighborhoodMembershipRequest::query()
            ->where('neighborhood_group_id', $group->id)
            ->with(['user', 'neighborhoodGroup.municipality'])
            ->orderByDesc('created_at');

        if (isset($validated['status'])) {
            $query->where('status', $validated['status']);
        }

        return MembershipRequestResource::collection($query->paginate());
    }

    public function approve(
        Request $request,
        NeighborhoodMembershipRequest $membershipRequest,
        ApproveMembershipRequestService $approve,
    ): MembershipRequestResource|JsonResponse {
        $this->authorize('approve', $membershipRequest);

        $data = $request->validate([
            'review_note' => ['nullable', 'string', 'max:500'],
        ]);

        try {
            $result = $approve->execute($membershipRequest, $request->user(), $data['review_note'] ?? null);

            return new MembershipRequestResource($result);
        } catch (MembershipRequestException $e) {
            return response()->json(['message' => $e->getMessage()], $e->httpStatus);
        }
    }

    public function reject(
        Request $request,
        NeighborhoodMembershipRequest $membershipRequest,
        RejectMembershipRequestService $reject,
    ): MembershipRequestResource|JsonResponse {
        $this->authorize('reject', $membershipRequest);

        $data = $request->validate([
            'review_note' => ['nullable', 'string', 'max:500'],
        ]);

        try {
            $result = $reject->execute($membershipRequest, $request->user(), $data['review_note'] ?? null);

            return new MembershipRequestResource($result);
        } catch (MembershipRequestException $e) {
            return response()->json(['message' => $e->getMessage()], $e->httpStatus);
        }
    }

    public function membershipContext(Request $request, NeighborhoodGroup $group): NeighborhoodGroupResource|JsonResponse
    {
        if (! $request->user()->can('viewMembershipContext', $group)) {
            abort(403);
        }

        $group->load('municipality');

        return new NeighborhoodGroupResource($group);
    }
}
