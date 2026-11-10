<?php

namespace App\Filament\Resources\MunicipalPosts\Pages;

use App\Filament\Resources\MunicipalPosts\MunicipalPostResource;
use Filament\Actions\CreateAction;
use Filament\Resources\Pages\ListRecords;

class ListMunicipalPosts extends ListRecords
{
    protected static string $resource = MunicipalPostResource::class;

    protected function getHeaderActions(): array
    {
        return [CreateAction::make()];
    }
}
