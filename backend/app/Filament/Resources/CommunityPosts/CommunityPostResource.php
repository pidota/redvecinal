<?php

namespace App\Filament\Resources\CommunityPosts;

use App\Domains\Posts\Models\Post;
use App\Filament\Resources\CommunityPosts\Pages\ListCommunityPosts;
use App\Filament\Resources\CommunityPosts\Tables\CommunityPostsTable;
use BackedEnum;
use Filament\Facades\Filament;
use Filament\Resources\Resource;
use Illuminate\Auth\Access\Response;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\SoftDeletingScope;

class CommunityPostResource extends Resource
{
    protected static ?string $model = Post::class;

    protected static ?string $navigationLabel = 'Publicaciones comunitarias';

    protected static ?string $modelLabel = 'publicación comunitaria';

    protected static ?string $pluralModelLabel = 'publicaciones comunitarias';

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedNewspaper;

    public static function getEloquentQuery(): Builder
    {
        $query = parent::getEloquentQuery()
            ->withoutGlobalScopes([SoftDeletingScope::class])
            ->whereNotNull('neighborhood_group_id');

        $user = Filament::auth()->user();
        if ($user && ! $user->isSuperAdmin()) {
            $query->whereIn('municipality_id', $user->activeMunicipalityMemberships()->pluck('municipality_id'));
        }

        return $query;
    }

    public static function table(Table $table): Table
    {
        return CommunityPostsTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListCommunityPosts::route('/'),
        ];
    }

    public static function canCreate(): bool
    {
        return false;
    }

    public static function canEdit($record): bool
    {
        return false;
    }

    public static function canViewAny(): bool
    {
        return Filament::auth()->user()?->can('posts.community.view') ?? false;
    }

    public static function getViewAnyAuthorizationResponse(): Response
    {
        return static::canViewAny()
            ? Response::allow()
            : Response::deny('No autorizado para ver publicaciones comunitarias.');
    }
}
