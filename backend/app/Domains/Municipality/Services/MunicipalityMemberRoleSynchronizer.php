<?php

namespace App\Domains\Municipality\Services;

use App\Domains\Municipality\Enums\MunicipalityMemberRole;
use App\Domains\Municipality\Enums\MunicipalityMemberStatus;
use App\Domains\Municipality\Models\MunicipalityMember;
use App\Models\User;

class MunicipalityMemberRoleSynchronizer
{
    public const MUNICIPAL_PANEL_ROLE = 'administrador-municipal';

    public function sync(User $user): void
    {
        if ($user->isSuperAdmin()) {
            return;
        }

        $hasActiveAdministrador = MunicipalityMember::query()
            ->where('user_id', $user->id)
            ->where('status', MunicipalityMemberStatus::Active)
            ->where('role', MunicipalityMemberRole::Administrador)
            ->exists();

        if ($hasActiveAdministrador) {
            if (! $user->hasRole(self::MUNICIPAL_PANEL_ROLE)) {
                $user->assignRole(self::MUNICIPAL_PANEL_ROLE);
            }

            return;
        }

        if ($user->hasRole(self::MUNICIPAL_PANEL_ROLE)) {
            $user->removeRole(self::MUNICIPAL_PANEL_ROLE);
        }
    }
}
