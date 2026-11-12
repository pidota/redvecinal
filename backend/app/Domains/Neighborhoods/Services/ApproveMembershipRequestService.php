<?php

namespace App\Domains\Neighborhoods\Services;

use App\Domains\Neighborhoods\Enums\MembershipRequestStatus;
use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Exceptions\MembershipRequestException;
use App\Domains\Neighborhoods\Exceptions\NeighborhoodDomainException;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodMembershipRequest;
use App\Domains\Neighborhoods\Support\GroupUserMembershipLocks;
use App\Domains\Neighborhoods\Support\MembershipEventRecorder;
use App\Domains\Neighborhoods\Support\MembershipRequestDatabase;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;

class ApproveMembershipRequestService
{
    public function __construct(
        private readonly MembershipEventRecorder $recorder,
        private readonly ApproveGroupMemberService $approveGroupMember,
    ) {}

    public function execute(NeighborhoodMembershipRequest $request, User $actor, ?string $reviewNote = null): NeighborhoodMembershipRequest
    {
        $request->loadMissing('neighborhoodGroup');
        $group = $request->neighborhoodGroup;

        if ($group === null || ! $group->isAdministrable()) {
            throw new MembershipRequestException('La junta no permite aprobaciones en su estado actual.', 422);
        }

        return DB::transaction(function () use ($request, $actor, $reviewNote, $group) {
            GroupUserMembershipLocks::lockMembershipRequestsForPair($group->id, $request->user_id);

            $lockedRequest = NeighborhoodMembershipRequest::query()
                ->whereKey($request->id)
                ->lockForUpdate()
                ->firstOrFail();

            if ($lockedRequest->status !== MembershipRequestStatus::Pending) {
                throw new MembershipRequestException('Solo se pueden aprobar solicitudes pendientes.', 409);
            }

            $member = GroupUserMembershipLocks::lockGroupMemberForPair($group->id, $lockedRequest->user_id);

            if ($member?->status === MembershipStatus::Active) {
                throw new MembershipRequestException('El usuario ya es integrante activo de la junta.', 409);
            }

            if ($member?->status === MembershipStatus::Pending) {
                try {
                    $this->approveGroupMember->execute($member, $actor);
                } catch (NeighborhoodDomainException $e) {
                    throw new MembershipRequestException($e->getMessage(), 409);
                }
            } elseif ($member === null) {
                try {
                    $member = GroupMember::query()->create([
                        'municipality_id' => $group->municipality_id,
                        'neighborhood_group_id' => $group->id,
                        'user_id' => $lockedRequest->user_id,
                        'membership_role' => MembershipRole::Member,
                        'status' => MembershipStatus::Active,
                        'approved_by' => $actor->id,
                        'approved_at' => now(),
                        'joined_at' => now(),
                    ]);
                } catch (QueryException $e) {
                    if (MembershipRequestDatabase::isRetriableConflict($e)) {
                        throw new MembershipRequestException('El usuario ya es integrante activo de la junta.', 409);
                    }

                    throw $e;
                }
                $this->recorder->record($member, 'approved', $actor, ['source' => 'membership_request']);
            } else {
                $member->update([
                    'membership_role' => MembershipRole::Member,
                    'status' => MembershipStatus::Active,
                    'approved_by' => $actor->id,
                    'approved_at' => now(),
                    'joined_at' => $member->joined_at ?? now(),
                ]);
                $this->recorder->record($member->fresh(), 'reactivated', $actor, ['source' => 'membership_request']);
            }

            $lockedRequest->update([
                'status' => MembershipRequestStatus::Approved,
                'review_note' => $reviewNote,
                'reviewed_by' => $actor->id,
                'reviewed_at' => now(),
            ]);

            return $lockedRequest->fresh(['neighborhoodGroup.municipality', 'user', 'reviewer']);
        });
    }
}
