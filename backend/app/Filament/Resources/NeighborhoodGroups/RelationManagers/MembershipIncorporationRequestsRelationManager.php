<?php

namespace App\Filament\Resources\NeighborhoodGroups\RelationManagers;

use App\Domains\Neighborhoods\Enums\MembershipRequestStatus;
use App\Domains\Neighborhoods\Models\NeighborhoodMembershipRequest;
use Filament\Facades\Filament;
use Filament\Resources\RelationManagers\RelationManager;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Model;

class MembershipIncorporationRequestsRelationManager extends RelationManager
{
    protected static string $relationship = 'membershipRequests';

    protected static ?string $title = 'Solicitudes de incorporación';

    protected static ?string $modelLabel = 'solicitud de incorporación';

    protected static ?string $pluralModelLabel = 'solicitudes de incorporación';

    public static function canViewForRecord(Model $ownerRecord, string $pageClass): bool
    {
        $user = Filament::auth()->user();

        if ($user === null) {
            return false;
        }

        return $user->can('viewAny', [NeighborhoodMembershipRequest::class, $ownerRecord]);
    }

    public static function getBadge(Model $ownerRecord, string $pageClass): ?string
    {
        $user = Filament::auth()->user();

        if ($user === null || ! $user->can('viewAny', [NeighborhoodMembershipRequest::class, $ownerRecord])) {
            return null;
        }

        $pending = $ownerRecord->membershipRequests()
            ->where('status', MembershipRequestStatus::Pending)
            ->count();

        return $pending > 0 ? (string) $pending : null;
    }

    public function table(Table $table): Table
    {
        return $table
            ->recordTitleAttribute('id')
            ->heading('Solicitudes de incorporación (app móvil)')
            ->description(
                'Petición enviada por un vecino desde la aplicación móvil. '
                .'No constituye una membresía del panel hasta su aprobación en la app. '
                .'La pestaña Integrantes muestra membresías gestionadas en este panel.'
            )
            ->modifyQueryUsing(fn (Builder $query): Builder => $query->with('user')->orderByDesc('created_at'))
            ->columns([
                TextColumn::make('user.name')
                    ->label('Solicitante'),
                TextColumn::make('user.email')
                    ->label('Correo')
                    ->visible(fn (): bool => (bool) auth()->user()?->can('group-members.view')),
                TextColumn::make('created_at')
                    ->label('Fecha de solicitud')
                    ->dateTime('d/m/Y H:i'),
                TextColumn::make('status')
                    ->label('Estado')
                    ->badge()
                    ->formatStateUsing(fn (MembershipRequestStatus $state): string => match ($state) {
                        MembershipRequestStatus::Pending => 'Pendiente',
                        MembershipRequestStatus::Approved => 'Aprobada',
                        MembershipRequestStatus::Rejected => 'Rechazada',
                        MembershipRequestStatus::Cancelled => 'Cancelada',
                    }),
                TextColumn::make('resolved_at')
                    ->label('Fecha de resolución')
                    ->state(function (NeighborhoodMembershipRequest $record): ?\Illuminate\Support\Carbon {
                        return match ($record->status) {
                            MembershipRequestStatus::Approved => $record->reviewed_at,
                            MembershipRequestStatus::Rejected => $record->rejected_at,
                            MembershipRequestStatus::Cancelled => $record->cancelled_at,
                            default => null,
                        };
                    })
                    ->dateTime('d/m/Y H:i')
                    ->placeholder('—'),
            ])
            ->filters([
                SelectFilter::make('status')
                    ->label('Estado')
                    ->options([
                        MembershipRequestStatus::Pending->value => 'Pendiente',
                        MembershipRequestStatus::Approved->value => 'Aprobada',
                        MembershipRequestStatus::Rejected->value => 'Rechazada',
                        MembershipRequestStatus::Cancelled->value => 'Cancelada',
                    ])
                    ->default(MembershipRequestStatus::Pending->value),
            ])
            ->headerActions([])
            ->recordActions([])
            ->toolbarActions([])
            ->emptyStateHeading('Sin solicitudes para mostrar')
            ->emptyStateDescription(
                'No hay solicitudes de incorporación móvil con el filtro actual. '
                .'Los vecinos envían estas solicitudes desde la app; para incorporar manualmente use la pestaña Integrantes.'
            );
    }
}