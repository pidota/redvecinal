<?php

namespace App\Domains\Neighborhoods\Support;

use App\Domains\Municipality\Enums\MunicipalityMemberRole;
use App\Domains\Municipality\Enums\MunicipalityMemberStatus;
use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Enums\NeighborhoodGroupStatus;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;

/**
 * Consulta de juntas donde el usuario puede listar/revisar solicitudes de incorporación.
 * Debe permanecer alineada con {@see \App\Domains\Neighborhoods\Policies\NeighborhoodMembershipRequestPolicy::canReviewMembershipRequests()}.
 */
final class ReviewableNeighborhoodGroupsQuery
{
    public static function forUser(User $user): Builder
    {
        $query = NeighborhoodGroup::query()
            ->where('status', NeighborhoodGroupStatus::Active);

        if ($user->isSuperAdmin()) {
            return $query;
        }

        return $query->where(function (Builder $outer) use ($user) {
            $outer->whereHas('memberships', function (Builder $membership) use ($user) {
                $membership
                    ->where('user_id', $user->id)
                    ->where('status', MembershipStatus::Active)
                    ->where('membership_role', MembershipRole::President);
            });

            if ($user->can('group-members.approve') && $user->hasRole('administrador-municipal')) {
                $municipalityIds = $user->municipalityMemberships()
                    ->where('status', MunicipalityMemberStatus::Active)
                    ->where('role', MunicipalityMemberRole::Administrador)
                    ->pluck('municipality_id');

                if ($municipalityIds->isNotEmpty()) {
                    $outer->orWhere(function (Builder $municipal) use ($user, $municipalityIds) {
                        $municipal
                            ->whereIn('municipality_id', $municipalityIds)
                            ->whereDoesntHave('memberships', function (Builder $membership) use ($user) {
                                $membership
                                    ->where('user_id', $user->id)
                                    ->where('status', MembershipStatus::Active)
                                    ->where('membership_role', MembershipRole::Moderator);
                            });
                    });
                }
            }
        });
    }
}
