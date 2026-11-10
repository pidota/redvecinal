<?php

namespace App\Filament\Resources\MunicipalityMembers\Schemas;

use App\Domains\Municipality\Enums\MunicipalityMemberRole;
use App\Domains\Municipality\Enums\MunicipalityMemberStatus;
use App\Domains\Municipality\Models\Municipality;
use Filament\Facades\Filament;
use Filament\Forms\Components\Select;
use Filament\Schemas\Schema;

class MunicipalityMemberForm
{
    public static function configure(Schema $schema): Schema
    {
        return $schema
            ->components([
                Select::make('municipality_id')
                    ->label('Municipalidad')
                    ->relationship('municipality', 'name')
                    ->default(fn (): ?int => Municipality::query()->where('slug', 'chepica')->value('id'))
                    ->required(),
                Select::make('user_id')
                    ->label('Usuario')
                    ->relationship('user', 'name')
                    ->searchable()
                    ->preload()
                    ->required(),
                Select::make('role')
                    ->label('Cargo')
                    ->options(fn (): array => Filament::auth()->user()?->isSuperAdmin()
                        ? [
                            MunicipalityMemberRole::Administrador->value => 'Administrador',
                            MunicipalityMemberRole::Funcionario->value => 'Funcionario',
                        ]
                        : [
                            MunicipalityMemberRole::Funcionario->value => 'Funcionario',
                        ])
                    ->required(),
                Select::make('status')
                    ->label('Estado')
                    ->options([
                        MunicipalityMemberStatus::Active->value => 'Activo',
                        MunicipalityMemberStatus::Inactive->value => 'Inactivo',
                    ])
                    ->default(MunicipalityMemberStatus::Active->value)
                    ->required(),
            ]);
    }
}
