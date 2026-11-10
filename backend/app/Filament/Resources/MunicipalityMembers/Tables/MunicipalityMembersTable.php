<?php

namespace App\Filament\Resources\MunicipalityMembers\Tables;

use App\Domains\Municipality\Enums\MunicipalityMemberRole;
use App\Domains\Municipality\Enums\MunicipalityMemberStatus;
use Filament\Actions\BulkActionGroup;
use Filament\Actions\DeleteBulkAction;
use Filament\Actions\EditAction;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;

class MunicipalityMembersTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('municipality.name')->label('Municipalidad')->sortable(),
                TextColumn::make('user.name')->label('Usuario')->searchable(),
                TextColumn::make('user.email')->label('Correo'),
                TextColumn::make('role')
                    ->label('Cargo')
                    ->formatStateUsing(fn (MunicipalityMemberRole $state) => match ($state) {
                        MunicipalityMemberRole::Administrador => 'Administrador',
                        MunicipalityMemberRole::Funcionario => 'Funcionario',
                    }),
                TextColumn::make('status')
                    ->label('Estado')
                    ->badge()
                    ->formatStateUsing(fn (MunicipalityMemberStatus $state) => $state === MunicipalityMemberStatus::Active ? 'Activo' : 'Inactivo'),
            ])
            ->recordActions([
                EditAction::make(),
            ])
            ->toolbarActions([
                BulkActionGroup::make([
                    DeleteBulkAction::make(),
                ]),
            ]);
    }
}
