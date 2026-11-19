<?php

namespace App\Filament\Resources\PostReports;

use App\Domains\Posts\Models\PostReport;
use App\Filament\Resources\PostReports\Pages\ListPostReports;
use App\Filament\Resources\PostReports\Pages\ViewPostReport;
use App\Filament\Resources\PostReports\Schemas\PostReportInfolist;
use App\Filament\Resources\PostReports\Tables\PostReportsTable;
use BackedEnum;
use Filament\Facades\Filament;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Auth\Access\Response;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

class PostReportResource extends Resource
{
    protected static ?string $model = PostReport::class;

    protected static ?string $navigationLabel = 'Reportes de contenido';

    protected static ?string $modelLabel = 'reporte';

    protected static ?string $pluralModelLabel = 'reportes';

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedFlag;

    public static function getEloquentQuery(): Builder
    {
        $query = parent::getEloquentQuery()
            ->with([
                'municipality:id,name',
                'post' => fn ($postQuery) => $postQuery->with([
                    'currentPublishedRevision:id,post_id,title',
                ]),
            ]);

        $user = Filament::auth()->user();

        if ($user && $user->isSuperAdmin()) {
            return $query;
        }

        $municipalityIds = $user?->activeAdministratorMunicipalityIds() ?? collect();

        return $query->whereIn('municipality_id', $municipalityIds);
    }

    public static function infolist(Schema $schema): Schema
    {
        return PostReportInfolist::configure($schema);
    }

    public static function table(Table $table): Table
    {
        return PostReportsTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListPostReports::route('/'),
            'view' => ViewPostReport::route('/{record}'),
        ];
    }

    public static function canViewAny(): bool
    {
        return Filament::auth()->user()?->can('viewAny', PostReport::class) ?? false;
    }

    public static function canView(Model $record): bool
    {
        return Filament::auth()->user()?->can('view', $record) ?? false;
    }

    public static function canCreate(): bool
    {
        return false;
    }

    public static function canEdit(Model $record): bool
    {
        return false;
    }

    public static function canDelete(Model $record): bool
    {
        return false;
    }

    public static function canDeleteAny(): bool
    {
        return false;
    }

    public static function canForceDelete(Model $record): bool
    {
        return false;
    }

    public static function canForceDeleteAny(): bool
    {
        return false;
    }

    public static function canRestore(Model $record): bool
    {
        return false;
    }

    public static function canRestoreAny(): bool
    {
        return false;
    }

    public static function canReplicate(Model $record): bool
    {
        return false;
    }

    public static function getViewAnyAuthorizationResponse(): Response
    {
        return static::canViewAny()
            ? Response::allow()
            : Response::deny('No autorizado para ver reportes de contenido.');
    }

    public static function getViewAuthorizationResponse(Model $record): Response
    {
        return static::canView($record)
            ? Response::allow()
            : Response::deny('No autorizado para ver este reporte.');
    }
}
