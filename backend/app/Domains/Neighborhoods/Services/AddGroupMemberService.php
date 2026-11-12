<?php

namespace App\Domains\Neighborhoods\Services;

use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Exceptions\NeighborhoodDomainException;
use App\Domains\Neighborhoods\Enums\MembershipRequestStatus;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Models\NeighborhoodMembershipRequest;
use App\Domains\Neighborhoods\Support\GroupUserMembershipLocks;
use App\Domains\Neighborhoods\Support\MembershipEventRecorder;
use App\Models\User;
use Illuminate\Support\Facades\DB;

class AddGroupMemberService
{
    public function __construct(private readonly MembershipEventRecorder $recorder) {}

    public function execute(
        NeighborhoodGroup $group,
        User $user,
        User $actor,
        MembershipStatus $initialStatus = MembershipStatus::Pending,
        MembershipRole $role = MembershipRole::Member,
    ): GroupMember {
        if (! $group->isAdministrable()) {
            throw new NeighborhoodDomainException('La junta no permite incorporaciones en su estado actual.');
        }

        return DB::transaction(function () use ($group, $user, $actor, $initialStatus, $role) {
            GroupUserMembershipLocks::lockMembershipRequestsForPair($group->id, $user->id);

            $existing = GroupUserMembershipLocks::lockGroupMemberForPair($group->id, $user->id);

            if ($existing) {
                throw new NeighborhoodDomainException('El usuario ya tiene una membresía en esta junta.');
            }

            $openRequest = NeighborhoodMembershipRequest::query()
                ->where('neighborhood_group_id', $group->id)
                ->where('user_id', $user->id)
                ->where('status', MembershipRequestStatus::Pending)
                ->exists();

            if ($openRequest) {
                throw new NeighborhoodDomainException(
                    'El usuario tiene una solicitud de incorporación pendiente en la app móvil.'
                );
            }

            if ($role === MembershipRole::President) {
                throw new NeighborhoodDomainException('La presidencia solo puede asignarse mediante el flujo de cambio de presidente.');
            }

            $member = GroupMember::query()->create([
                'municipality_id' => $group->municipality_id,
                'neighborhood_group_id' => $group->id,
                'user_id' => $user->id,
                'membership_role' => $role,
                'status' => $initialStatus,
                'joined_at' => $initialStatus === MembershipStatus::Active ? now() : null,
                'approved_by' => $initialStatus === MembershipStatus::Active ? $actor->id : null,
                'approved_at' => $initialStatus === MembershipStatus::Active ? now() : null,
            ]);

            $this->recorder->record($member, 'member_added', $actor, [
                'status' => $initialStatus->value,
                'role' => $role->value,
            ]);

            return $member;
        });
    }
}
