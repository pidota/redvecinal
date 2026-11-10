<?php

namespace App\Filament\Resources\PostReports;

use App\Domains\Posts\Models\PostReport;
use App\Filament\Resources\PostReports\Pages\ListPostReports;
use App\Filament\Resources\PostReports\Tables\PostReportsTable;
use BackedEnum;
use Filament\Facades\Filament;
use Filament\Resources\Resource;
use Illuminate\Auth\Access\Response;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

class PostReportResource extends Resource
{
    protected static ?string $model = PostReport::class;

    protected static ?string $navigationLabel = 'Reportes de contenido';

    protected static ?string $modelLabel = 'reporte';

    protected static ?string $pluralModelLabel = 'reportes';

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedFlag;

    public static function getEloquentQuery(): Builder
    {
        $query = parent::getEloquentQuery();

        $user = Filament::auth()->user();
        if ($user && ! $user->isSuperAdmin()) {
            $query->whereIn('municipality_id', $user->activeMunicipalityMemberships()->pluck('municipality_id'));
        }

        return $query;
    }

    public static function table(Table $table): Table
    {
        return PostReportsTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListPostReports::route('/'),
        ];
    }

    public static function canViewAny(): bool
    {
        return Filament::auth()->user()?->can('posts.reports.view') ?? false;
    }

    public static function getViewAnyAuthorizationResponse(): Response
    {
        return static::canViewAny()
            ? Response::allow()
            : Response::deny('No autorizado para ver reportes de contenido.');
    }
}
