<?php

namespace App\Domains\Neighborhoods\Services;

use App\Domains\Neighborhoods\Enums\MembershipRequestStatus;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Exceptions\MembershipRequestException;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Models\NeighborhoodMembershipRequest;
use App\Domains\Neighborhoods\Support\GroupUserMembershipLocks;
use App\Domains\Neighborhoods\Support\MembershipRejectionCooldown;
use App\Domains\Neighborhoods\Support\MembershipRequestDatabase;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;

class SubmitMembershipRequestService
{
    public function __construct(private readonly MembershipRejectionCooldown $cooldown) {}

    public function execute(NeighborhoodGroup $group, User $user, ?string $requestNote = null): NeighborhoodMembershipRequest
    {
        if (! $group->isAdministrable()) {
            throw new MembershipRequestException('La junta no acepta solicitudes en su estado actual.', 422);
        }

        return DB::transaction(function () use ($group, $user, $requestNote) {
            GroupUserMembershipLocks::lockMembershipRequestsForPair($group->id, $user->id);

            $member = GroupUserMembershipLocks::lockGroupMemberForPair($group->id, $user->id);

            if ($member?->status === MembershipStatus::Active) {
                throw new MembershipRequestException('Ya eres integrante activo de esta junta.', 409);
            }

            if ($member?->status === MembershipStatus::Pending) {
                throw new MembershipRequestException(
                    'Ya existe una solicitud pendiente administrada para esta junta.',
                    409
                );
            }

            $pending = NeighborhoodMembershipRequest::query()
                ->where('neighborhood_group_id', $group->id)
                ->where('user_id', $user->id)
                ->where('status', MembershipRequestStatus::Pending)
                ->exists();

            if ($pending) {
                throw new MembershipRequestException('Ya tienes una solicitud pendiente para esta junta.', 409);
            }

            $this->cooldown->assertUnlocked($group, $user);

            try {
                return NeighborhoodMembershipRequest::query()->create([
                    'municipality_id' => $group->municipality_id,
                    'neighborhood_group_id' => $group->id,
                    'user_id' => $user->id,
                    'status' => MembershipRequestStatus::Pending,
                    'request_note' => $requestNote,
                ]);
            } catch (QueryException $e) {
                if (MembershipRequestDatabase::isRetriableConflict($e)) {
                    throw new MembershipRequestException('Ya tienes una solicitud pendiente para esta junta.', 409);
                }

                throw $e;
            }
        });
    }
}
