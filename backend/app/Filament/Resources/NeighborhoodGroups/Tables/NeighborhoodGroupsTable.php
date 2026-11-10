<?php

namespace App\Filament\Resources\NeighborhoodGroups\Tables;

use App\Domains\Neighborhoods\Enums\NeighborhoodGroupStatus;
use Filament\Actions\BulkActionGroup;
use Filament\Actions\DeleteBulkAction;
use Filament\Actions\EditAction;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Filters\TrashedFilter;
use Filament\Tables\Table;

class NeighborhoodGroupsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('name')
                    ->label('Nombre')
                    ->searchable()
                    ->sortable(),
                TextColumn::make('municipality.name')
                    ->label('Municipalidad')
                    ->sortable(),
                TextColumn::make('status')
                    ->label('Estado')
                    ->badge()
                    ->formatStateUsing(fn (NeighborhoodGroupStatus $state): string => match ($state) {
                        NeighborhoodGroupStatus::Active => 'Activa',
                        NeighborhoodGroupStatus::Inactive => 'Inactiva',
                        NeighborhoodGroupStatus::Suspended => 'Suspendida',
                    }),
                TextColumn::make('memberships_count')
                    ->label('Integrantes')
                    ->counts('memberships'),
                TextColumn::make('updated_at')
                    ->label('Actualizado')
                    ->dateTime('d/m/Y H:i')
                    ->sortable(),
            ])
            ->filters([
                SelectFilter::make('status')
                    ->label('Estado')
                    ->options([
                        NeighborhoodGroupStatus::Active->value => 'Activa',
                        NeighborhoodGroupStatus::Inactive->value => 'Inactiva',
                        NeighborhoodGroupStatus::Suspended->value => 'Suspendida',
                    ]),
                SelectFilter::make('municipality_id')
                    ->label('Municipalidad')
                    ->relationship('municipality', 'name'),
                TrashedFilter::make()
                    ->label('Eliminadas'),
            ])
            ->recordActions([
                EditAction::make(),
            ])
            ->toolbarActions([
                BulkActionGroup::make([
                    DeleteBulkAction::make()
                        ->label('Eliminar (lógico)'),
                ]),
            ]);
    }
}
