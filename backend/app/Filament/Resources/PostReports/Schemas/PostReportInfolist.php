<?php

namespace App\Filament\Resources\PostReports\Schemas;

use App\Domains\Posts\Enums\PostReportStatus;
use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Models\PostReport;
use Filament\Infolists\Components\TextEntry;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Schema;

class PostReportInfolist
{
    public static function configure(Schema $schema): Schema
    {
        return $schema
            ->components([
                Section::make('Reporte')
                    ->schema([
                        TextEntry::make('id')->label('ID'),
                        TextEntry::make('status')
                            ->label('Estado')
                            ->badge()
                            ->formatStateUsing(fn (PostReportStatus $state): string => $state->label())
                            ->color(fn (PostReportStatus $state): string => $state->color()),
                        TextEntry::make('municipality.name')
                            ->label('Municipalidad')
                            ->placeholder('—'),
                        TextEntry::make('created_at')
                            ->label('Creado')
                            ->dateTime('d/m/Y H:i'),
                        TextEntry::make('reason_code')
                            ->label('Motivo')
                            ->formatStateUsing(fn (?string $state): string => PostReport::labelForReasonCode($state)),
                        TextEntry::make('details')
                            ->label('Detalles del reportante')
                            ->placeholder('Sin detalles')
                            ->columnSpanFull(),
                    ])
                    ->columns(2),
                Section::make('Publicación')
                    ->schema([
                        TextEntry::make('post_id')
                            ->label('ID publicación')
                            ->placeholder('—'),
                        TextEntry::make('post_availability')
                            ->label('Disponibilidad')
                            ->state(fn (PostReport $record): string => self::postAvailability($record)),
                        TextEntry::make('post.currentPublishedRevision.title')
                            ->label('Título')
                            ->placeholder('Publicación no disponible'),
                        TextEntry::make('post.author.name')
                            ->label('Autor')
                            ->placeholder('—'),
                        TextEntry::make('post.status')
                            ->label('Estado de la publicación')
                            ->formatStateUsing(fn (?PostStatus $state): string => $state?->value ?? '—'),
                        TextEntry::make('post.currentPublishedRevision.body')
                            ->label('Contenido')
                            ->placeholder('Sin contenido')
                            ->columnSpanFull(),
                    ])
                    ->columns(2),
                Section::make('Seguimiento')
                    ->schema([
                        TextEntry::make('reporter.name')
                            ->label('Reportante')
                            ->placeholder('—'),
                        TextEntry::make('resolver.name')
                            ->label('Funcionario responsable')
                            ->placeholder('—'),
                        TextEntry::make('resolved_at')
                            ->label('Fecha de resolución')
                            ->dateTime('d/m/Y H:i')
                            ->placeholder('—'),
                        TextEntry::make('resolution_note')
                            ->label('Fundamento')
                            ->placeholder('—')
                            ->columnSpanFull(),
                    ])
                    ->columns(2),
            ]);
    }

    private static function postAvailability(PostReport $record): string
    {
        if ($record->post_id === null) {
            return 'Sin publicación asociada';
        }

        if ($record->post === null) {
            return 'Publicación no disponible';
        }

        if ($record->post->trashed()) {
            return 'Publicación eliminada';
        }

        return 'Disponible';
    }
}
