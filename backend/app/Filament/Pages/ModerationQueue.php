<?php

namespace App\Filament\Pages;

use App\Domains\Posts\Enums\PostRevisionStatus;
use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Models\Post;
use BackedEnum;
use Filament\Facades\Filament;
use Filament\Pages\Page;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Concerns\InteractsWithTable;
use Filament\Tables\Contracts\HasTable;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;

class ModerationQueue extends Page implements HasTable
{
    use InteractsWithTable;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedQueueList;

    protected static ?string $navigationLabel = 'Cola de moderación';

    protected static ?string $title = 'Cola de moderación (consulta)';

    protected string $view = 'filament.pages.moderation-queue';

    public static function canAccess(): bool
    {
        return Filament::auth()->user()?->can('posts.community.view') ?? false;
    }

    public function table(Table $table): Table
    {
        return $table
            ->query($this->moderationQuery())
            ->columns([
                TextColumn::make('neighborhoodGroup.name')->label('Junta'),
                TextColumn::make('author.name')->label('Autor'),
                TextColumn::make('status')->badge(),
                TextColumn::make('submitted_at')->dateTime(),
            ])
            ->paginated();
    }

    protected function moderationQuery(): Builder
    {
        $query = Post::query()
            ->with(['neighborhoodGroup', 'author'])
            ->whereNotNull('neighborhood_group_id')
            ->where(function (Builder $builder) {
                $builder->where('status', PostStatus::Pending)
                    ->orWhereHas('revisions', fn (Builder $r) => $r->where('status', PostRevisionStatus::Pending));
            });

        $user = Filament::auth()->user();
        if ($user && ! $user->isSuperAdmin()) {
            $query->whereIn('municipality_id', $user->activeMunicipalityMemberships()->pluck('municipality_id'));
        }

        return $query;
    }
}
