<?php

namespace App\Filament\Resources\NeighborhoodGroups\Schemas;

use App\Domains\Municipality\Models\Municipality;
use App\Domains\Neighborhoods\Enums\NeighborhoodGroupStatus;
use Filament\Facades\Filament;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\Textarea;
use Filament\Forms\Components\TextInput;
use Filament\Schemas\Schema;
use Illuminate\Support\Str;

class NeighborhoodGroupForm
{
    public static function configure(Schema $schema): Schema
    {
        return $schema
            ->components([
                Select::make('municipality_id')
                    ->label('Municipalidad')
                    ->relationship('municipality', 'name')
                    ->searchable()
                    ->preload()
                    ->required()
                    ->default(fn (): ?int => Municipality::query()->where('slug', 'chepica')->value('id'))
                    ->disabled(fn (): bool => ! Filament::auth()->user()?->isSuperAdmin()),
                TextInput::make('name')
                    ->label('Nombre')
                    ->required()
                    ->maxLength(180)
                    ->live(onBlur: true)
                    ->afterStateUpdated(function ($set, ?string $state, $get): void {
                        if (blank($get('slug'))) {
                            $set('slug', Str::slug((string) $state));
                        }
                    }),
                TextInput::make('slug')
                    ->label('Identificador (slug)')
                    ->required()
                    ->maxLength(180),
                TextInput::make('registration_number')
                    ->label('Nº inscripción')
                    ->maxLength(50),
                Textarea::make('description')
                    ->label('Descripción')
                    ->columnSpanFull(),
                TextInput::make('address')
                    ->label('Dirección')
                    ->maxLength(255),
                TextInput::make('contact_email')
                    ->label('Correo de contacto')
                    ->email()
                    ->maxLength(255),
                TextInput::make('contact_phone')
                    ->label('Teléfono de contacto')
                    ->tel()
                    ->maxLength(30),
                Select::make('status')
                    ->label('Estado')
                    ->options([
                        NeighborhoodGroupStatus::Active->value => 'Activa',
                        NeighborhoodGroupStatus::Inactive->value => 'Inactiva',
                        NeighborhoodGroupStatus::Suspended->value => 'Suspendida',
                    ])
                    ->required()
                    ->default(NeighborhoodGroupStatus::Active->value),
            ]);
    }
}
