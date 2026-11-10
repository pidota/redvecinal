<?php

namespace App\Filament\Resources\MunicipalPosts\Tables;

use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;

class MunicipalPostsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('id')->sortable(),
                TextColumn::make('currentPublishedRevision.title')->label('Título')->searchable(),
                TextColumn::make('status')->badge(),
                TextColumn::make('published_at')->dateTime()->sortable(),
            ])
            ->defaultSort('published_at', 'desc');
    }
}
