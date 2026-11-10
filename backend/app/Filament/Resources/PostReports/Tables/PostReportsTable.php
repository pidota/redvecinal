<?php

namespace App\Filament\Resources\PostReports\Tables;

use App\Domains\Posts\Enums\PostReportStatus;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;

class PostReportsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('id')->sortable(),
                TextColumn::make('post_id')->label('Publicación'),
                TextColumn::make('reason_code'),
                TextColumn::make('status')->badge(),
                TextColumn::make('created_at')->dateTime(),
            ])
            ->defaultSort('created_at', 'desc');
    }
}
