<?php

namespace App\Filament\Resources\PostReports\Pages;

use App\Domains\Posts\Enums\PostReportStatus;
use App\Domains\Posts\Exceptions\PostDomainException;
use App\Domains\Posts\Models\PostReport;
use App\Domains\Posts\Services\TransitionPostReportService;
use App\Filament\Resources\PostReports\PostReportResource;
use App\Models\User;
use Filament\Actions\Action;
use Filament\Facades\Filament;
use Filament\Forms\Components\Textarea;
use Filament\Notifications\Notification;
use Filament\Resources\Pages\ViewRecord;
use Filament\Support\Icons\Heroicon;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Database\Eloquent\Model;

class ViewPostReport extends ViewRecord
{
    protected static string $resource = PostReportResource::class;

    protected function getHeaderActions(): array
    {
        return [
            Action::make('reviewReport')
                ->label('Tomar en revisión')
                ->icon(Heroicon::OutlinedClipboardDocumentCheck)
                ->color('info')
                ->requiresConfirmation()
                ->modalHeading('Tomar reporte en revisión')
                ->modalDescription('El reporte quedará asignado a tu usuario. No se resuelve ni se descarta.')
                ->modalSubmitActionLabel('Tomar en revisión')
                ->visible(fn (): bool => $this->canTransitionTo(PostReportStatus::Reviewing))
                ->authorize(fn (): bool => $this->canManageReport())
                ->successNotification(null)
                ->action(function (): void {
                    $this->applyReportTransition(PostReportStatus::Reviewing);
                }),
            Action::make('resolveReport')
                ->label('Resolver')
                ->icon(Heroicon::OutlinedCheckCircle)
                ->color('success')
                ->requiresConfirmation()
                ->modalHeading('Resolver reporte')
                ->modalDescription('El reporte se cerrará como resuelto. Esta acción no oculta ni elimina la publicación.')
                ->modalSubmitActionLabel('Resolver')
                ->schema($this->resolutionNoteSchema())
                ->visible(fn (): bool => $this->canTransitionTo(PostReportStatus::Resolved))
                ->authorize(fn (): bool => $this->canManageReport())
                ->successNotification(null)
                ->action(function (array $data): void {
                    $this->applyReportTransition(
                        PostReportStatus::Resolved,
                        $data['resolution_note'] ?? null,
                    );
                }),
            Action::make('dismissReport')
                ->label('Descartar')
                ->icon(Heroicon::OutlinedXCircle)
                ->color('danger')
                ->requiresConfirmation()
                ->modalHeading('Descartar reporte')
                ->modalDescription('El reporte se cerrará como descartado. No se elimina el reporte ni la publicación.')
                ->modalSubmitActionLabel('Descartar')
                ->schema($this->resolutionNoteSchema())
                ->visible(fn (): bool => $this->canTransitionTo(PostReportStatus::Dismissed))
                ->authorize(fn (): bool => $this->canManageReport())
                ->successNotification(null)
                ->action(function (array $data): void {
                    $this->applyReportTransition(
                        PostReportStatus::Dismissed,
                        $data['resolution_note'] ?? null,
                    );
                }),
        ];
    }

    protected function resolveRecord(int|string $key): Model
    {
        return $this->loadReportRelations(parent::resolveRecord($key));
    }

    /**
     * @return array<int, Textarea>
     */
    private function resolutionNoteSchema(): array
    {
        return [
            Textarea::make('resolution_note')
                ->label('Fundamento')
                ->required()
                ->rows(5)
                ->maxLength(TransitionPostReportService::RESOLUTION_NOTE_MAX_LENGTH)
                ->dehydrateStateUsing(fn (?string $state): string => trim((string) $state))
                ->helperText('Obligatorio. Máximo '.TransitionPostReportService::RESOLUTION_NOTE_MAX_LENGTH.' caracteres.'),
        ];
    }

    private function canManageReport(): bool
    {
        $user = Filament::auth()->user();
        $record = $this->getRecord();

        return $user instanceof User && $user->can('resolve', $record);
    }

    private function canTransitionTo(PostReportStatus $target): bool
    {
        $record = $this->getRecord();
        if (! $record instanceof PostReport) {
            return false;
        }

        $status = $record->status instanceof PostReportStatus
            ? $record->status
            : PostReportStatus::from((string) $record->status);

        return $this->canManageReport()
            && app(TransitionPostReportService::class)->isAllowedTransition($status, $target);
    }

    private function applyReportTransition(PostReportStatus $targetStatus, ?string $resolutionNote = null): void
    {
        $actor = Filament::auth()->user();
        if (! $actor instanceof User) {
            $this->notifyAuthorizationFailure();

            return;
        }

        try {
            app(TransitionPostReportService::class)->execute(
                $this->getRecord(),
                $actor,
                $targetStatus,
                $resolutionNote,
            );
        } catch (AuthorizationException) {
            $this->notifyAuthorizationFailure();

            return;
        } catch (PostDomainException) {
            Notification::make()
                ->title('El reporte cambió de estado o la transición no está permitida. Actualiza la página.')
                ->danger()
                ->send();

            $this->refreshRecord();

            return;
        }

        $this->refreshRecord();

        Notification::make()
            ->title($this->successTitle($targetStatus))
            ->success()
            ->send();
    }

    private function notifyAuthorizationFailure(): void
    {
        Notification::make()
            ->title('No tienes autorización para gestionar este reporte.')
            ->danger()
            ->send();
    }

    private function successTitle(PostReportStatus $status): string
    {
        return match ($status) {
            PostReportStatus::Reviewing => 'Reporte tomado en revisión',
            PostReportStatus::Resolved => 'Reporte resuelto',
            PostReportStatus::Dismissed => 'Reporte descartado',
            default => 'Reporte actualizado',
        };
    }

    private function refreshRecord(): void
    {
        $record = $this->getRecord();
        if (! $record instanceof PostReport) {
            return;
        }

        $record->refresh();
        $this->loadReportRelations($record);
    }

    private function loadReportRelations(Model $record): Model
    {
        $record->load([
            'municipality:id,name',
            'reporter:id,name',
            'resolver:id,name',
            'post' => fn ($query) => $query->with([
                'author:id,name',
                'currentPublishedRevision:id,post_id,title,body',
            ]),
        ]);

        return $record;
    }
}
