<?php

namespace App\Filament\Resources\ChatMessageReports;

use App\Domains\Chat\Models\ChatMessageReport;
use App\Filament\Resources\ChatMessageReports\Pages\ListChatMessageReports;
use App\Filament\Resources\ChatMessageReports\Tables\ChatMessageReportsTable;
use BackedEnum;
use Filament\Facades\Filament;
use Filament\Resources\Resource;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Auth\Access\Response;
use Illuminate\Database\Eloquent\Builder;

class ChatMessageReportResource extends Resource
{
    protected static ?string $model = ChatMessageReport::class;

    protected static ?string $navigationLabel = 'Reportes de chat';

    protected static ?string $modelLabel = 'reporte de chat';

    protected static ?string $pluralModelLabel = 'reportes de chat';

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedChatBubbleLeftRight;

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
        return ChatMessageReportsTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListChatMessageReports::route('/'),
        ];
    }

    public static function canViewAny(): bool
    {
        return Filament::auth()->user()?->can('chat.reports.view') ?? false;
    }

    public static function getViewAnyAuthorizationResponse(): Response
    {
        return static::canViewAny()
            ? Response::allow()
            : Response::deny('No autorizado para ver reportes de chat.');
    }
}
