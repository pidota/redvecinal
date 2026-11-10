<?php

namespace App\Domains\Posts\Models;

use App\Domains\Municipality\Models\Municipality;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Posts\Enums\PostStatus;
use App\Domains\Posts\Enums\PostVisibility;
use App\Domains\Posts\Enums\PostRevisionStatus;
use App\Models\User;
use Database\Factories\PostFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\UseFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Database\Eloquent\SoftDeletes;

#[Fillable([
    'municipality_id',
    'neighborhood_group_id',
    'author_id',
    'category_id',
    'status',
    'visibility',
    'current_published_revision_id',
    'submitted_at',
    'published_at',
    'hidden_at',
    'archived_at',
    'comments_enabled',
])]
#[UseFactory(PostFactory::class)]
class Post extends Model
{
    use HasFactory, SoftDeletes;

    protected function casts(): array
    {
        return [
            'status' => PostStatus::class,
            'visibility' => PostVisibility::class,
            'submitted_at' => 'datetime',
            'published_at' => 'datetime',
            'hidden_at' => 'datetime',
            'archived_at' => 'datetime',
            'comments_enabled' => 'boolean',
        ];
    }

    public function municipality(): BelongsTo
    {
        return $this->belongsTo(Municipality::class);
    }

    public function neighborhoodGroup(): BelongsTo
    {
        return $this->belongsTo(NeighborhoodGroup::class, 'neighborhood_group_id');
    }

    public function author(): BelongsTo
    {
        return $this->belongsTo(User::class, 'author_id');
    }

    public function category(): BelongsTo
    {
        return $this->belongsTo(PostCategory::class, 'category_id');
    }

    public function revisions(): HasMany
    {
        return $this->hasMany(PostRevision::class);
    }

    public function currentPublishedRevision(): BelongsTo
    {
        return $this->belongsTo(PostRevision::class, 'current_published_revision_id');
    }

    public function pendingRevision(): HasOne
    {
        return $this->hasOne(PostRevision::class)->where('status', PostRevisionStatus::Pending);
    }

    public function comments(): HasMany
    {
        return $this->hasMany(PostComment::class);
    }

    public function reactions(): HasMany
    {
        return $this->hasMany(PostReaction::class);
    }

    public function moderationEvents(): HasMany
    {
        return $this->hasMany(PostModerationEvent::class);
    }

    public function isCommunity(): bool
    {
        return $this->neighborhood_group_id !== null;
    }

    public function isMunicipal(): bool
    {
        return $this->neighborhood_group_id === null;
    }

    public function allowsEngagement(): bool
    {
        return $this->status->allowsPublicInteraction();
    }
}
