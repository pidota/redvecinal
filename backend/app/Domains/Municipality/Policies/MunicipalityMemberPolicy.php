<?php

namespace App\Domains\Municipality\Policies;

use App\Domains\Municipality\Enums\MunicipalityMemberRole;
use App\Domains\Municipality\Models\MunicipalityMember;
use App\Models\User;

class MunicipalityMemberPolicy
{
    public function viewAny(User $user): bool
    {
        if ($user->isSuperAdmin()) {
            return true;
        }

        return $user->activeMunicipalityMemberships()
            ->where('role', MunicipalityMemberRole::Administrador)
            ->exists();
    }

    public function assignAdministradorRole(User $user, ?MunicipalityMember $record = null): bool
    {
        if (! $user->isSuperAdmin()) {
            return false;
        }

        if ($record && $record->user?->isSuperAdmin()) {
            return false;
        }

        return true;
    }

    public function manageTargetUser(User $actor, int $targetUserId): bool
    {
        if ($actor->isSuperAdmin()) {
            return true;
        }

        if ($actor->id === $targetUserId) {
            return false;
        }

        return $actor->hasRole('administrador-municipal');
    }

    public function view(User $user, MunicipalityMember $municipalityMember): bool
    {
        if ($user->isSuperAdmin()) {
            return true;
        }

        return $user->isMunicipalAdministratorFor($municipalityMember->municipality_id);
    }

    public function create(User $user): bool
    {
        if ($user->isSuperAdmin()) {
            return true;
        }

        return $user->activeMunicipalityMemberships()
            ->where('role', MunicipalityMemberRole::Administrador)
            ->exists();
    }

    public function update(User $user, MunicipalityMember $municipalityMember): bool
    {
        if ($user->isSuperAdmin()) {
            return true;
        }

        if ($user->id === $municipalityMember->user_id) {
            return false;
        }

        if ($municipalityMember->user?->isSuperAdmin()) {
            return false;
        }

        return $user->isMunicipalAdministratorFor($municipalityMember->municipality_id);
    }

    public function delete(User $user, MunicipalityMember $municipalityMember): bool
    {
        return $this->update($user, $municipalityMember);
    }
}
