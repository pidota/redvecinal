<?php

namespace App\Domains\Neighborhoods\Services;

use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Exceptions\NeighborhoodDomainException;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Support\MembershipEventRecorder;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;

class AssignPresidentService
{
    public function __construct(private readonly MembershipEventRecorder $recorder) {}

    public function execute(NeighborhoodGroup $group, User $newPresident, User $actor): GroupMember
    {
        if (! $group->isAdministrable()) {
            throw new NeighborhoodDomainException('La junta no permite cambios de presidencia en su estado actual.');
        }

        return DB::transaction(function () use ($group, $newPresident, $actor) {
            $group = NeighborhoodGroup::query()->whereKey($group->id)->lockForUpdate()->firstOrFail();

            $targetMembership = GroupMember::query()
                ->where('neighborhood_group_id', $group->id)
                ->where('user_id', $newPresident->id)
                ->lockForUpdate()
                ->first();

            if (! $targetMembership) {
                throw new NeighborhoodDomainException('El usuario debe ser integrante de la junta antes de asignarse como presidente.');
            }

            if ($targetMembership->status !== MembershipStatus::Active) {
                throw new NeighborhoodDomainException('Solo integrantes activos pueden ser presidentes.');
            }

            if ($targetMembership->status === MembershipStatus::Suspended) {
                throw new NeighborhoodDomainException('Un integrante suspendido no puede presidir.');
            }

            $currentPresident = GroupMember::query()
                ->where('neighborhood_group_id', $group->id)
                ->where('membership_role', MembershipRole::President)
                ->where('status', MembershipStatus::Active)
                ->lockForUpdate()
                ->first();

            if ($currentPresident && $currentPresident->user_id === $newPresident->id) {
                return $currentPresident;
            }

            if ($currentPresident) {
                $currentPresident->update(['membership_role' => MembershipRole::Member]);
                $this->recorder->record($currentPresident, 'president_demoted', $actor, [
                    'neighborhood_group_id' => $group->id,
                ]);
            }

            try {
                $targetMembership->update(['membership_role' => MembershipRole::President]);
            } catch (QueryException $exception) {
                if ($this->isDuplicatePresidentIndex($exception)) {
                    throw new NeighborhoodDomainException('La junta ya tiene un presidente activo.');
                }

                throw $exception;
            }

            $this->recorder->record($targetMembership, 'president_assigned', $actor, [
                'neighborhood_group_id' => $group->id,
                'user_id' => $newPresident->id,
            ]);

            return $targetMembership->fresh();
        });
    }

    private function isDuplicatePresidentIndex(QueryException $exception): bool
    {
        $message = $exception->getMessage();

        return str_contains($message, 'group_members_unique_active_president')
            || str_contains($message, '1062');
    }
}
