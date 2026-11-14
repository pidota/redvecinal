<?php

namespace App\Filament\Resources\NeighborhoodGroups\RelationManagers;

use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Exceptions\NeighborhoodDomainException;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Services\AddGroupMemberService;
use App\Domains\Neighborhoods\Services\ApproveGroupMemberService;
use App\Domains\Neighborhoods\Services\AssignPresidentService;
use App\Domains\Neighborhoods\Services\RejectGroupMemberService;
use App\Domains\Neighborhoods\Services\RemoveGroupMemberService;
use App\Domains\Neighborhoods\Services\SuspendGroupMemberService;
use App\Models\User;
use Filament\Actions\Action;
use Filament\Facades\Filament;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Notifications\Notification;
use Filament\Resources\RelationManagers\RelationManager;
use Filament\Schemas\Schema;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Table;
use Illuminate\Support\Facades\Hash;

class MembershipsRelationManager extends RelationManager
{
    protected static string $relationship = 'memberships';

    protected static ?string $title = 'Integrantes';

    protected static ?string $description = 'Membresías creadas o gestionadas desde este panel (incorporación manual). No incluye solicitudes enviadas por la app móvil.';

    public function form(Schema $schema): Schema
    {
        return $schema
            ->components([
                Select::make('user_id')
                    ->label('Usuario')
                    ->searchable()
                    ->getSearchResultsUsing(fn (string $search) => User::query()
                        ->where('name', 'like', "%{$search}%")
                        ->orWhere('email', 'like', "%{$search}%")
                        ->limit(50)
                        ->pluck('name', 'id'))
                    ->getOptionLabelUsing(fn ($value) => User::query()->find($value)?->name)
                    ->required(),
            ]);
    }

    public function table(Table $table): Table
    {
        return $table
            ->recordTitleAttribute('id')
            ->heading('Integrantes de la junta (panel municipal)')
            ->description(
                'Listado de membresías en esta junta. El estado «Pendiente (panel)» corresponde a una incorporación manual '
                .'esperando aprobación aquí. Las solicitudes de la app móvil se consultan en la pestaña «Solicitudes de incorporación».'
            )
            ->modifyQueryUsing(fn ($query) => $query->with(['user', 'approver']))
            ->columns([
                TextColumn::make('user.name')->label('Nombre'),
                TextColumn::make('user.email')->label('Correo'),
                TextColumn::make('membership_role')
                    ->label('Cargo')
                    ->formatStateUsing(fn (MembershipRole $state) => match ($state) {
                        MembershipRole::President => 'Presidente',
                        MembershipRole::Moderator => 'Moderador',
                        MembershipRole::Member => 'Vecino',
                    }),
                TextColumn::make('status')
                    ->label('Estado')
                    ->badge()
                    ->formatStateUsing(fn (MembershipStatus $state) => match ($state) {
                        MembershipStatus::Pending => 'Pendiente (panel)',
                        MembershipStatus::Active => 'Activo',
                        MembershipStatus::Rejected => 'Rechazado',
                        MembershipStatus::Suspended => 'Suspendido',
                        MembershipStatus::Left => 'Retirado',
                    }),
                TextColumn::make('approved_at')
                    ->label('Aprobación')
                    ->dateTime('d/m/Y'),
            ])
            ->headerActions([
                Action::make('addExisting')
                    ->label('Agregar usuario existente')
                    ->schema([
                        Select::make('user_id')
                            ->label('Usuario')
                            ->searchable()
                            ->getSearchResultsUsing(fn (string $search) => User::query()
                                ->where('name', 'like', "%{$search}%")
                                ->orWhere('email', 'like', "%{$search}%")
                                ->limit(50)
                                ->pluck('name', 'id'))
                            ->getOptionLabelUsing(fn ($value) => User::query()->find($value)?->name)
                            ->required(),
                    ])
                    ->authorize(fn (): bool => auth()->user()->can('create', [GroupMember::class, $this->getOwnerRecord()]))
                    ->action(function (array $data, AddGroupMemberService $service): void {
                        $user = User::query()->findOrFail($data['user_id']);

                        try {
                            $service->execute($this->getOwnerRecord(), $user, Filament::auth()->user());
                            Notification::make()
                                ->title('Integrante agregado (membresía pendiente de aprobación en panel)')
                                ->success()
                                ->send();
                        } catch (NeighborhoodDomainException $e) {
                            $this->notifyIncorporationConflict($e);
                        }
                    }),
                Action::make('createUser')
                    ->label('Crear usuario e incorporar')
                    ->schema([
                        TextInput::make('name')->label('Nombre')->required(),
                        TextInput::make('email')->label('Correo')->email()->required()->unique('users', 'email'),
                        TextInput::make('password')->label('Contraseña')->password()->required()->minLength(8),
                    ])
                    ->authorize(fn (): bool => auth()->user()->can('create', [GroupMember::class, $this->getOwnerRecord()]))
                    ->action(function (array $data, AddGroupMemberService $service): void {
                        $user = User::query()->create([
                            'name' => $data['name'],
                            'email' => $data['email'],
                            'password' => Hash::make($data['password']),
                        ]);

                        try {
                            $service->execute($this->getOwnerRecord(), $user, Filament::auth()->user());
                            Notification::make()
                                ->title('Usuario creado con membresía pendiente de aprobación en panel')
                                ->success()
                                ->send();
                        } catch (NeighborhoodDomainException $e) {
                            $this->notifyIncorporationConflict($e);
                        }
                    }),
            ])
            ->recordActions([
                Action::make('approve')
                    ->label('Aprobar incorporación (panel)')
                    ->visible(fn (GroupMember $record): bool => $record->status === MembershipStatus::Pending)
                    ->authorize(fn (GroupMember $record): bool => auth()->user()->can('approve', $record))
                    ->action(function (GroupMember $record, ApproveGroupMemberService $service): void {
                        $service->execute($record, Filament::auth()->user());
                        Notification::make()->title('Membresía del panel aprobada')->success()->send();
                    }),
                Action::make('reject')
                    ->label('Rechazar incorporación (panel)')
                    ->color('danger')
                    ->visible(fn (GroupMember $record): bool => $record->status === MembershipStatus::Pending)
                    ->authorize(fn (GroupMember $record): bool => auth()->user()->can('reject', $record))
                    ->action(function (GroupMember $record, RejectGroupMemberService $service): void {
                        $service->execute($record, Filament::auth()->user());
                        Notification::make()->title('Membresía del panel rechazada')->success()->send();
                    }),
                Action::make('suspend')
                    ->label('Suspender')
                    ->color('warning')
                    ->visible(fn (GroupMember $record): bool => $record->status === MembershipStatus::Active)
                    ->authorize(fn (GroupMember $record): bool => auth()->user()->can('suspend', $record))
                    ->action(function (GroupMember $record, SuspendGroupMemberService $service): void {
                        $service->execute($record, Filament::auth()->user());
                        Notification::make()->title('Integrante suspendido')->success()->send();
                    }),
                Action::make('remove')
                    ->label('Retirar')
                    ->color('gray')
                    ->authorize(fn (GroupMember $record): bool => auth()->user()->can('remove', $record))
                    ->requiresConfirmation()
                    ->action(function (GroupMember $record, RemoveGroupMemberService $service): void {
                        $service->execute($record, Filament::auth()->user());
                        Notification::make()->title('Integrante retirado')->success()->send();
                    }),
                Action::make('assignPresident')
                    ->label('Asignar presidente')
                    ->icon('heroicon-o-star')
                    ->visible(fn (GroupMember $record): bool => $record->status === MembershipStatus::Active)
                    ->authorize(fn (GroupMember $record): bool => auth()->user()->can('assignPresident', $record))
                    ->requiresConfirmation()
                    ->action(function (GroupMember $record, AssignPresidentService $service): void {
                        $service->execute($record->neighborhoodGroup, $record->user, Filament::auth()->user());
                        Notification::make()->title('Presidente asignado')->success()->send();
                    }),
            ]);
    }

    private function notifyIncorporationConflict(NeighborhoodDomainException $exception): void
    {
        $body = str_contains($exception->getMessage(), 'app móvil')
            ? 'Este vecino tiene una solicitud de incorporación pendiente en la app móvil para esta junta. '
                .'Revise la pestaña «Solicitudes de incorporación». La decisión debe tomarse desde la aplicación móvil o esperando a que el vecino cancele la solicitud.'
            : $exception->getMessage();

        Notification::make()
            ->title('No se pudo incorporar desde el panel')
            ->body($body)
            ->danger()
            ->send();
    }
}
