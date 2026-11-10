<?php

namespace App\Domains\Neighborhoods\Services;

use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Exceptions\NeighborhoodDomainException;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Support\MembershipEventRecorder;
use App\Models\User;
use Illuminate\Support\Facades\DB;

class RejectGroupMemberService
{
    public function __construct(private readonly MembershipEventRecorder $recorder) {}

    public function execute(GroupMember $member, User $actor): GroupMember
    {
        if ($member->status !== MembershipStatus::Pending) {
            throw new NeighborhoodDomainException('Solo se pueden rechazar solicitudes pendientes.');
        }

        return DB::transaction(function () use ($member, $actor) {
            $member = GroupMember::query()->whereKey($member->id)->lockForUpdate()->firstOrFail();
            $member->update(['status' => MembershipStatus::Rejected]);
            $this->recorder->record($member, 'rejected', $actor);

            return $member->fresh();
        });
    }
}
