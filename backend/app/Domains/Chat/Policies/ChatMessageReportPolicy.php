<?php

namespace App\Domains\Chat\Policies;

use App\Domains\Chat\Models\ChatMessageReport;
use App\Models\User;

class ChatMessageReportPolicy
{
    public function viewAny(User $user): bool
    {
        return $user->isSuperAdmin() || $user->can('chat.reports.view');
    }

    public function view(User $user, ChatMessageReport $report): bool
    {
        if ($user->isSuperAdmin()) {
            return $user->can('chat.reports.view');
        }

        return $user->can('chat.reports.view')
            && $user->isMunicipalAdministratorFor($report->municipality_id);
    }

    public function resolve(User $user, ChatMessageReport $report): bool
    {
        if ($user->isSuperAdmin()) {
            return $user->can('chat.reports.resolve');
        }

        return $user->can('chat.reports.resolve')
            && $user->isMunicipalAdministratorFor($report->municipality_id);
    }
}
