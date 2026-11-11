<?php

namespace App\Domains\Auth\Services;

use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Models\User;

/**
 * Reglas de acceso token Sanctum para la app móvil (no panel Filament).
 */
class MobileApiAccessService
{
    public function mayObtainMobileToken(User $user): bool
    {
        if ($user->isSuperAdmin()) {
            return true;
        }

        if ($user->activeMunicipalityMemberships()->exists()) {
            return true;
        }

        return $user->groupMemberships()->where('status', MembershipStatus::Active)->exists();
    }
}
