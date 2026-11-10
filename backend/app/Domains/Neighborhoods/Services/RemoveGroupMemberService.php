<?php

namespace App\Domains\Neighborhoods\Services;

use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Exceptions\NeighborhoodDomainException;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Support\MembershipEventRecorder;
use App\Models\User;
use Illuminate\Support\Facades\DB;

class RemoveGroupMemberService
{
    public function __construct(private readonly MembershipEventRecorder $recorder) {}

    public function execute(GroupMember $member, User $actor): GroupMember
    {
        if ($member->membership_role === MembershipRole::President && $member->status === MembershipStatus::Active) {
            throw new NeighborhoodDomainException('Debe reemplazar al presidente antes de retirarlo.');
        }

        return DB::transaction(function () use ($member, $actor) {
            $member = GroupMember::query()->whereKey($member->id)->lockForUpdate()->firstOrFail();
            $member->update(['status' => MembershipStatus::Left]);
            $this->recorder->record($member, 'left', $actor);

            return $member->fresh();
        });
    }
}
