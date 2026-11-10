<?php

namespace App\Domains\Neighborhoods\Services;

use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Exceptions\NeighborhoodDomainException;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Support\MembershipEventRecorder;
use App\Models\User;
use Illuminate\Support\Facades\DB;

class ApproveGroupMemberService
{
    public function __construct(private readonly MembershipEventRecorder $recorder) {}

    public function execute(GroupMember $member, User $actor): GroupMember
    {
        $member->loadMissing('neighborhoodGroup');

        if (! $member->neighborhoodGroup?->isAdministrable()) {
            throw new NeighborhoodDomainException('La junta no permite aprobaciones en su estado actual.');
        }

        if ($member->status !== MembershipStatus::Pending) {
            throw new NeighborhoodDomainException('Solo se pueden aprobar solicitudes pendientes.');
        }

        return DB::transaction(function () use ($member, $actor) {
            $member = GroupMember::query()->whereKey($member->id)->lockForUpdate()->firstOrFail();

            $member->update([
                'status' => MembershipStatus::Active,
                'approved_by' => $actor->id,
                'approved_at' => now(),
                'joined_at' => now(),
            ]);

            $this->recorder->record($member, 'approved', $actor);

            return $member->fresh();
        });
    }
}
