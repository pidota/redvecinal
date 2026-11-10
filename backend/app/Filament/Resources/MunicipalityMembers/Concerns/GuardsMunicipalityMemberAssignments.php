<?php

namespace App\Filament\Resources\MunicipalityMembers\Concerns;

use App\Domains\Municipality\Enums\MunicipalityMemberRole;
use App\Domains\Municipality\Models\MunicipalityMember;
use Filament\Facades\Filament;
use Illuminate\Validation\ValidationException;

trait GuardsMunicipalityMemberAssignments
{
    protected function guardMunicipalityMemberData(array $data, ?MunicipalityMember $record = null): array
    {
        $actor = Filament::auth()->user();

        if (! $actor) {
            throw ValidationException::withMessages(['auth' => 'No autenticado.']);
        }

        $targetUserId = (int) ($data['user_id'] ?? $record?->user_id);

        if (! $actor->isSuperAdmin() && $actor->id === $targetUserId) {
            throw ValidationException::withMessages([
                'user_id' => 'No puede gestionar su propia membresía municipal ni elevar sus permisos.',
            ]);
        }

        $role = $data['role'] ?? $record?->role?->value;

        if ($role === MunicipalityMemberRole::Administrador->value && ! $actor->isSuperAdmin()) {
            throw ValidationException::withMessages([
                'role' => 'Solo un superadministrador puede asignar el cargo de administrador municipal.',
            ]);
        }

        if (! $actor->isSuperAdmin()) {
            $municipalityId = (int) ($data['municipality_id'] ?? $record?->municipality_id);
            if (! $actor->isMunicipalAdministratorFor($municipalityId)) {
                throw ValidationException::withMessages([
                    'municipality_id' => 'No puede gestionar personal de otra municipalidad.',
                ]);
            }
        }

        return $data;
    }
}
