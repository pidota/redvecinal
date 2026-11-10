<?php

namespace App\Filament\Resources\MunicipalityMembers\Pages;

use App\Filament\Resources\MunicipalityMembers\MunicipalityMemberResource;
use Filament\Actions\CreateAction;
use Filament\Resources\Pages\ListRecords;

class ListMunicipalityMembers extends ListRecords
{
    protected static string $resource = MunicipalityMemberResource::class;

    protected function getHeaderActions(): array
    {
        return [
            CreateAction::make(),
        ];
    }
}
