<?php

namespace App\Domains\Neighborhoods\Services;

use App\Domains\Neighborhoods\Enums\MembershipRequestStatus;
use App\Domains\Neighborhoods\Exceptions\MembershipRequestException;
use App\Domains\Neighborhoods\Models\NeighborhoodMembershipRequest;
use App\Models\User;
use Illuminate\Support\Facades\DB;

class RejectMembershipRequestService
{
    public function execute(NeighborhoodMembershipRequest $request, User $actor, ?string $reviewNote = null): NeighborhoodMembershipRequest
    {
        return DB::transaction(function () use ($request, $actor, $reviewNote) {
            $locked = NeighborhoodMembershipRequest::query()
                ->whereKey($request->id)
                ->lockForUpdate()
                ->firstOrFail();

            if ($locked->status !== MembershipRequestStatus::Pending) {
                throw new MembershipRequestException('Solo se pueden rechazar solicitudes pendientes.', 409);
            }

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
