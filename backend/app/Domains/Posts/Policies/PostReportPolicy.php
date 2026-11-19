<?php

namespace App\Domains\Posts\Policies;

use App\Domains\Municipality\Enums\MunicipalityMemberRole;
use App\Domains\Municipality\Enums\MunicipalityMemberStatus;
use App\Domains\Posts\Models\PostReport;
use App\Models\User;

class PostReportPolicy
{
    public function viewAny(User $user): bool
    {
        if (! $user->can('posts.reports.view')) {
            return false;
        }

        if ($user->isSuperAdmin()) {
            return true;
        }

        return $this->administersAnyMunicipality($user);
    }

    public function view(User $user, PostReport $report): bool
    {
        if (! $user->can('posts.reports.view')) {
            return false;
        }

        if ($user->isSuperAdmin()) {
            return true;
        }

        return $user->isMunicipalAdministratorFor($report->municipality_id);
    }

    public function resolve(User $user, PostReport $report): bool
    {
        if (! $user->can('posts.reports.resolve')) {
            return false;
        }

        if ($user->isSuperAdmin()) {
            return true;
        }

        return $user->isMunicipalAdministratorFor($report->municipality_id);
    }

    private function administersAnyMunicipality(User $user): bool
    {
        if (! $user->hasRole('administrador-municipal')) {
            return false;
        }

        return $user->municipalityMemberships()
            ->where('status', MunicipalityMemberStatus::Active)
            ->where('role', MunicipalityMemberRole::Administrador)
            ->exists();
    }
}
