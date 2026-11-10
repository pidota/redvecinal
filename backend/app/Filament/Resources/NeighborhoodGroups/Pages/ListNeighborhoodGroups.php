<?php

namespace App\Filament\Resources\NeighborhoodGroups\Pages;

use App\Filament\Resources\NeighborhoodGroups\NeighborhoodGroupResource;
use Filament\Actions\CreateAction;
use Filament\Resources\Pages\ListRecords;

class ListNeighborhoodGroups extends ListRecords
{
    protected static string $resource = NeighborhoodGroupResource::class;

    protected function getHeaderActions(): array
    {
        return [
            CreateAction::make(),
        ];
    }
}
