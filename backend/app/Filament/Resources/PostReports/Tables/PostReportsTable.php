<?php

namespace App\Filament\Resources\PostReports\Tables;

use App\Domains\Posts\Enums\PostReportStatus;
use App\Domains\Posts\Models\PostReport;
use Filament\Actions\ViewAction;
use Filament\Facades\Filament;
use Filament\Forms\Components\DatePicker;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\Filter;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

class PostReportsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->columns([
                TextColumn::make('id')
                    ->label('ID')
                    ->sortable()
                    ->searchable(),
                TextColumn::make('post.currentPublishedRevision.title')
                    ->label('Publicación')
                    ->limit(40)
                    ->placeholder('Publicación no disponible')
                    ->searchable(query: function (Builder $query, string $search): Builder {
                        return $query->whereHas(
                            'post.currentPublishedRevision',
                            fn (Builder $revisionQuery) => $revisionQuery->where('title', 'like', "%{$search}%")
                        );
                    }),
                TextColumn::make('reason_code')
                    ->label('Motivo')
                    ->formatStateUsing(fn (?string $state): string => PostReport::labelForReasonCode($state))
                    ->tooltip(fn (PostReport $record): ?string => self::reasonTooltip($record))
                    ->searchable(),
                TextColumn::make('status')
                    ->label('Estado')
                    ->badge()
                    ->formatStateUsing(fn (PostReportStatus $state): string => $state->label())
                    ->color(fn (PostReportStatus $state): string => $state->color()),
                TextColumn::make('municipality.name')
                    ->label('Municipalidad')
                    ->placeholder('—')
                    ->toggleable(),
                TextColumn::make('created_at')
                    ->label('Creado')
                    ->dateTime('d/m/Y H:i')
                    ->sortable(),
                TextColumn::make('resolved_at')
                    ->label('Resolución')
                    ->dateTime('d/m/Y H:i')
                    ->placeholder('—')
                    ->sortable(),
            ])
            ->filters([
                SelectFilter::make('status')
                    ->label('Estado')
                    ->options([
                        PostReportStatus::Open->value => PostReportStatus::Open->label(),
                        PostReportStatus::Reviewing->value => PostReportStatus::Reviewing->label(),
                        PostReportStatus::Resolved->value => PostReportStatus::Resolved->label(),
                        PostReportStatus::Dismissed->value => PostReportStatus::Dismissed->label(),
                    ]),
                Filter::make('created_at')
                    ->label('Fecha de creación')
                    ->form([
                        DatePicker::make('from')->label('Desde'),
                        DatePicker::make('until')->label('Hasta'),
                    ])
                    ->query(function (Builder $query, array $data): Builder {
                        return $query
                            ->when($data['from'] ?? null, fn (Builder $q, $date): Builder => $q->whereDate('created_at', '>=', $date))
                            ->when($data['until'] ?? null, fn (Builder $q, $date): Builder => $q->whereDate('created_at', '<=', $date));
                    }),
                SelectFilter::make('municipality_id')
                    ->label('Municipalidad')
                    ->relationship('municipality', 'name')
                    ->searchable()
                    ->preload()
                    ->visible(fn (): bool => Filament::auth()->user()?->isSuperAdmin() ?? false),
            ])
            ->recordActions([
                ViewAction::make(),
            ])
            ->toolbarActions([])
            ->defaultSort('created_at', 'desc');
    }

    private static function reasonTooltip(PostReport $record): ?string
    {
        $label = PostReport::labelForReasonCode($record->reason_code);

        return $label === $record->reason_code ? null : $record->reason_code;
    }
}
