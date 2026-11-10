<?php

namespace App\Filament\Resources\MunicipalityMembers\Pages;

use App\Filament\Resources\MunicipalityMembers\Concerns\GuardsMunicipalityMemberAssignments;
use App\Filament\Resources\MunicipalityMembers\MunicipalityMemberResource;
use Filament\Resources\Pages\CreateRecord;

class CreateMunicipalityMember extends CreateRecord
{
    use GuardsMunicipalityMemberAssignments;

    protected static string $resource = MunicipalityMemberResource::class;

    protected function mutateFormDataBeforeCreate(array $data): array
    {
        return $this->guardMunicipalityMemberData($data);
    }
}
