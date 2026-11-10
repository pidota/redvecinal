<?php

namespace App\Filament\Resources\NeighborhoodGroups;

use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Filament\Resources\NeighborhoodGroups\Pages\CreateNeighborhoodGroup;
use App\Filament\Resources\NeighborhoodGroups\Pages\EditNeighborhoodGroup;
use App\Filament\Resources\NeighborhoodGroups\Pages\ListNeighborhoodGroups;
use App\Filament\Resources\NeighborhoodGroups\RelationManagers\MembershipsRelationManager;
use App\Filament\Resources\NeighborhoodGroups\Schemas\NeighborhoodGroupForm;
use App\Filament\Resources\NeighborhoodGroups\Tables\NeighborhoodGroupsTable;
use BackedEnum;
use Filament\Facades\Filament;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\SoftDeletingScope;

class NeighborhoodGroupResource extends Resource
{
    protected static ?string $model = NeighborhoodGroup::class;

    protected static ?string $navigationLabel = 'Juntas de vecinos';

    protected static ?string $modelLabel = 'junta de vecinos';

    protected static ?string $pluralModelLabel = 'juntas de vecinos';

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedUserGroup;

    protected static ?string $recordTitleAttribute = 'name';

    public static function form(Schema $schema): Schema
    {
        return NeighborhoodGroupForm::configure($schema);
    }

    public static function table(Table $table): Table
    {
        return NeighborhoodGroupsTable::configure($table);
    }

    public static function getRelations(): array
    {
        return [
            MembershipsRelationManager::class,
        ];
    }

    public static function getPages(): array
    {
        return [
            'index' => ListNeighborhoodGroups::route('/'),
            'create' => CreateNeighborhoodGroup::route('/create'),
            'edit' => EditNeighborhoodGroup::route('/{record}/edit'),
        ];
    }

    public static function getEloquentQuery(): Builder
    {
        $query = parent::getEloquentQuery()->withoutGlobalScopes([SoftDeletingScope::class]);

        $user = Filament::auth()->user();

        if ($user && ! $user->isSuperAdmin()) {
            $municipalityIds = $user->activeMunicipalityMemberships()->pluck('municipality_id');
            $query->whereIn('municipality_id', $municipalityIds);
        }

        return $query;
    }
}
