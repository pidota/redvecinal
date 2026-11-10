<?php

namespace App\Filament\Resources\MunicipalityMembers\Pages;

use App\Filament\Resources\MunicipalityMembers\Concerns\GuardsMunicipalityMemberAssignments;
use App\Filament\Resources\MunicipalityMembers\MunicipalityMemberResource;
use Filament\Actions\DeleteAction;
use Filament\Resources\Pages\EditRecord;

class EditMunicipalityMember extends EditRecord
{
    use GuardsMunicipalityMemberAssignments;

    protected static string $resource = MunicipalityMemberResource::class;

    protected function getHeaderActions(): array
    {
        return [
            DeleteAction::make(),
        ];
    }

    protected function mutateFormDataBeforeSave(array $data): array
    {
        return $this->guardMunicipalityMemberData($data, $this->getRecord());
    }
}
