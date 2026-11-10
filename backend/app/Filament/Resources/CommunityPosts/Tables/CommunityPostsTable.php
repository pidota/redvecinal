<?php

namespace App\Filament\Resources\CommunityPosts\Tables;

use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Services\HidePostService;
use App\Domains\Posts\Services\RestorePostService;
use Filament\Actions\Action;
use Filament\Facades\Filament;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;

class CommunityPostsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('neighborhoodGroup.name')->label('Junta'),
                TextColumn::make('currentPublishedRevision.title')->label('Título'),
                TextColumn::make('status')->badge(),
                TextColumn::make('published_at')->dateTime(),
            ])
            ->recordActions([
                Action::make('hide')
                    ->label('Ocultar')
                    ->visible(fn ($record) => $record->status === PostStatus::Published)
                    ->authorize(fn ($record) => Filament::auth()->user()?->can('hide', $record) ?? false)
                    ->requiresConfirmation()
                    ->action(function ($record): void {
                        app(HidePostService::class)->execute(
                            $record,
                            Filament::auth()->user(),
                            'Ocultado desde panel municipal',
                        );
                    }),
                Action::make('restore')
                    ->label('Restaurar')
                    ->visible(fn ($record) => $record->status === PostStatus::Hidden)
                    ->authorize(fn ($record) => Filament::auth()->user()?->can('restore', $record) ?? false)
                    ->requiresConfirmation()
                    ->action(function ($record): void {
                        app(RestorePostService::class)->execute(
                            $record,
                            Filament::auth()->user(),
                        );
                    }),
            ]);
    }
}
