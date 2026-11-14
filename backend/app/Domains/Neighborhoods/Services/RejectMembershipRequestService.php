<?php

namespace App\Domains\Neighborhoods\Services;

use App\Domains\Neighborhoods\Enums\MembershipRequestStatus;
use App\Domains\Neighborhoods\Exceptions\MembershipRequestException;
use App\Domains\Neighborhoods\Models\NeighborhoodMembershipRequest;
use App\Domains\Neighborhoods\Support\GroupUserMembershipLocks;
use App\Domains\Neighborhoods\Support\MembershipRequestConcurrency;
use App\Models\User;

class RejectMembershipRequestService
{
    public function execute(NeighborhoodMembershipRequest $request, User $actor, ?string $reviewNote = null): NeighborhoodMembershipRequest
    {
        $request->loadMissing('neighborhoodGroup');

        return MembershipRequestConcurrency::runTransactional(function () use ($request, $actor, $reviewNote) {
            $groupId = $request->neighborhood_group_id;
            $userId = $request->user_id;

            GroupUserMembershipLocks::lockMembershipRequestsForPair($groupId, $userId);

            $locked = NeighborhoodMembershipRequest::query()
                ->whereKey($request->id)
                ->lockForUpdate()
                ->firstOrFail();

            if ($locked->status !== MembershipRequestStatus::Pending) {
                if (
                    MembershipRequestConcurrency::shouldReconcileDeadlock()
                    && $locked->status === MembershipRequestStatus::Rejected
                    && $locked->reviewed_by === $actor->id
                ) {
                    return $locked->fresh(['neighborhoodGroup.municipality', 'user', 'reviewer']);
                }

                throw new MembershipRequestException('Solo se pueden rechazar solicitudes pendientes.', 409);
            }

            GroupUserMembershipLocks::lockGroupMemberForPair($groupId, $locked->user_id);

            $now = now();
            $locked->update([
                'status' => MembershipRequestStatus::Rejected,
                'review_note' => $reviewNote,
                'reviewed_by' => $actor->id,
                'reviewed_at' => $now,
                'rejected_at' => $now,
            ]);

            return $locked->fresh(['neighborhoodGroup.municipality', 'user', 'reviewer']);
        });
    }
}
