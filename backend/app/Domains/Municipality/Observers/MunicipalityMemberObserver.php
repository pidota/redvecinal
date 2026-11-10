<?php

namespace App\Domains\Municipality\Observers;

use App\Domains\Municipality\Models\MunicipalityMember;
use App\Domains\Municipality\Services\MunicipalityMemberRoleSynchronizer;

class MunicipalityMemberObserver
{
    public function __construct(
        private readonly MunicipalityMemberRoleSynchronizer $synchronizer,
    ) {}

    public function saved(MunicipalityMember $member): void
    {
        $this->synchronizer->sync($member->user);
    }

    public function deleted(MunicipalityMember $member): void
    {
        $this->synchronizer->sync($member->user);
    }
}
