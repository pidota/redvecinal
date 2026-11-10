<?php

namespace App\Filament\Resources\NeighborhoodGroups\Pages;

use App\Filament\Resources\NeighborhoodGroups\NeighborhoodGroupResource;
use Filament\Actions\DeleteAction;
use Filament\Actions\ForceDeleteAction;
use Filament\Actions\RestoreAction;
use Filament\Resources\Pages\EditRecord;

class EditNeighborhoodGroup extends EditRecord
{
    protected static string $resource = NeighborhoodGroupResource::class;

    protected function getHeaderActions(): array
    {
        return [
            DeleteAction::make(),
            ForceDeleteAction::make(),
            RestoreAction::make(),
        ];
    }
}
