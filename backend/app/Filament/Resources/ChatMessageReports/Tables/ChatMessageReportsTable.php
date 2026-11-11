<?php

namespace App\Filament\Resources\ChatMessageReports\Tables;

use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;

class ChatMessageReportsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('id')->sortable(),
                TextColumn::make('reason_code')->label('Motivo'),
                TextColumn::make('status')->badge(),
                TextColumn::make('created_at')->dateTime(),
            ])
            ->defaultSort('created_at', 'desc');
    }
}
