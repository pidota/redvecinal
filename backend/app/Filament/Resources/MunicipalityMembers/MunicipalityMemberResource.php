<?php

namespace App\Filament\Resources\MunicipalityMembers;

use App\Domains\Municipality\Models\MunicipalityMember;
use App\Filament\Resources\MunicipalityMembers\Pages\CreateMunicipalityMember;
use App\Filament\Resources\MunicipalityMembers\Pages\EditMunicipalityMember;
use App\Filament\Resources\MunicipalityMembers\Pages\ListMunicipalityMembers;
use App\Filament\Resources\MunicipalityMembers\Schemas\MunicipalityMemberForm;
use App\Filament\Resources\MunicipalityMembers\Tables\MunicipalityMembersTable;
use BackedEnum;
use Filament\Facades\Filament;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

class MunicipalityMemberResource extends Resource
{
    protected static ?string $model = MunicipalityMember::class;

    protected static ?string $navigationLabel = 'Personal municipal';

    protected static ?string $modelLabel = 'miembro municipal';

    protected static ?string $pluralModelLabel = 'personal municipal';

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedBuildingOffice;

    public static function form(Schema $schema): Schema
    {
        return MunicipalityMemberForm::configure($schema);
    }

    public static function table(Table $table): Table
    {
        return MunicipalityMembersTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListMunicipalityMembers::route('/'),
            'create' => CreateMunicipalityMember::route('/create'),
            'edit' => EditMunicipalityMember::route('/{record}/edit'),
        ];
    }

    public static function getEloquentQuery(): Builder
    {
        $query = parent::getEloquentQuery();
        $user = Filament::auth()->user();

        if ($user && ! $user->isSuperAdmin()) {
            $municipalityIds = $user->activeMunicipalityMemberships()->pluck('municipality_id');
            $query->whereIn('municipality_id', $municipalityIds);
        }

        return $query;
    }
}
