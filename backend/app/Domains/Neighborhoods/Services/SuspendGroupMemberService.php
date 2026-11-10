<?php

namespace App\Domains\Neighborhoods\Services;

use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Exceptions\NeighborhoodDomainException;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Support\MembershipEventRecorder;
use App\Models\User;
use Illuminate\Support\Facades\DB;

class SuspendGroupMemberService
{
    public function __construct(private readonly MembershipEventRecorder $recorder) {}

    public function execute(GroupMember $member, User $actor): GroupMember
    {
        if ($member->status !== MembershipStatus::Active) {
            throw new NeighborhoodDomainException('Solo se pueden suspender integrantes activos.');
        }

        if ($member->membership_role === MembershipRole::President) {
            throw new NeighborhoodDomainException('Debe reemplazar al presidente antes de suspenderlo.');
        }

        return DB::transaction(function () use ($member, $actor) {
            $member = GroupMember::query()->whereKey($member->id)->lockForUpdate()->firstOrFail();
            $member->update(['status' => MembershipStatus::Suspended]);
            $this->recorder->record($member, 'suspended', $actor);

            return $member->fresh();
        });
    }
}
