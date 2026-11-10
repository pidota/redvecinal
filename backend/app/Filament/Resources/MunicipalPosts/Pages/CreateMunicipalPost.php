<?php

namespace App\Filament\Resources\MunicipalPosts\Pages;

use App\Domains\Municipality\Models\Municipality;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostCategory;
use App\Domains\Posts\Services\PublishOfficialPostService;
use App\Filament\Resources\MunicipalPosts\MunicipalPostResource;
use Filament\Facades\Filament;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\Textarea;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Toggle;
use Filament\Resources\Pages\CreateRecord;
use Filament\Schemas\Schema;

class CreateMunicipalPost extends CreateRecord
{
    protected static string $resource = MunicipalPostResource::class;

    public function form(Schema $schema): Schema
    {
        $user = Filament::auth()->user();
        $municipalityQuery = Municipality::query();
        if ($user && ! $user->isSuperAdmin()) {
            $municipalityQuery->whereIn('id', $user->activeMunicipalityMemberships()->pluck('municipality_id'));
        }

        return $schema->components([
            Select::make('municipality_id')
                ->label('Municipio')
                ->options($municipalityQuery->pluck('name', 'id'))
                ->required(),
            Select::make('category_id')
                ->label('Categoría')
                ->options(PostCategory::query()->where('is_active', true)->orderBy('sort_order')->pluck('name', 'id'))
                ->required(),
            TextInput::make('title')->required()->maxLength(200),
            Textarea::make('body')->required()->rows(10)->label('Contenido (Markdown)'),
            Toggle::make('comments_enabled')->default(true)->label('Comentarios habilitados'),
        ]);
    }

    protected function handleRecordCreation(array $data): Post
    {
        $municipality = Municipality::query()->findOrFail($data['municipality_id']);
        $author = Filament::auth()->user();

        $this->authorize('createMunicipal', [Post::class, $municipality->id]);

        return app(PublishOfficialPostService::class)->execute(
            $municipality,
            $author,
            (int) $data['category_id'],
            $data['title'],
            $data['body'],
            (bool) ($data['comments_enabled'] ?? true),
        );
    }
}
