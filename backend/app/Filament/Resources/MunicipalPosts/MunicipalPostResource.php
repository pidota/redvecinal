<?php

namespace App\Filament\Resources\MunicipalPosts;

use App\Domains\Posts\Models\Post;
use App\Filament\Resources\MunicipalPosts\Pages\CreateMunicipalPost;
use App\Filament\Resources\MunicipalPosts\Pages\ListMunicipalPosts;
use App\Filament\Resources\MunicipalPosts\Tables\MunicipalPostsTable;
use BackedEnum;
use Filament\Facades\Filament;
use Filament\Resources\Resource;
use Illuminate\Auth\Access\Response;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\SoftDeletingScope;

class MunicipalPostResource extends Resource
{
    protected static ?string $model = Post::class;

    protected static ?string $navigationLabel = 'Comunicados municipales';

    protected static ?string $modelLabel = 'comunicado municipal';

    protected static ?string $pluralModelLabel = 'comunicados municipales';

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedMegaphone;

    public static function getEloquentQuery(): Builder
    {
        $query = parent::getEloquentQuery()
            ->withoutGlobalScopes([SoftDeletingScope::class])
            ->whereNull('neighborhood_group_id');

        $user = Filament::auth()->user();
        if ($user && ! $user->isSuperAdmin()) {
            $query->whereIn('municipality_id', $user->activeMunicipalityMemberships()->pluck('municipality_id'));
        }

        return $query;
    }

    public static function table(Table $table): Table
    {
        return MunicipalPostsTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListMunicipalPosts::route('/'),
            'create' => CreateMunicipalPost::route('/create'),
        ];
    }

    public static function canViewAny(): bool
    {
        $user = Filament::auth()->user();

        return $user?->can('posts.municipal.view') ?? false;
    }

    public static function canCreate(): bool
    {
        $user = Filament::auth()->user();

        return $user?->can('posts.municipal.create') ?? false;
    }

    public static function getViewAnyAuthorizationResponse(): Response
    {
        return static::canViewAny()
            ? Response::allow()
            : Response::deny('No autorizado para ver comunicados municipales.');
    }

    public static function getCreateAuthorizationResponse(): Response
    {
        return static::canCreate()
            ? Response::allow()
            : Response::deny('No autorizado para crear comunicados municipales.');
    }
}
