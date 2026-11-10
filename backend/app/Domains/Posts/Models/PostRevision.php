<?php

namespace App\Domains\Posts\Models;

use App\Domains\Municipality\Models\Municipality;
use App\Domains\Posts\Enums\PostRevisionStatus;
use App\Models\User;
use Database\Factories\PostRevisionFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\UseFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable([
    'post_id',
    'municipality_id',
    'revision_number',
    'category_id',
    'title',
    'body',
    'status',
    'created_by',
    'reviewed_by',
    'submitted_at',
    'reviewed_at',
    'approved_at',
    'rejection_reason',
])]
#[UseFactory(PostRevisionFactory::class)]
class PostRevision extends Model
{
    use HasFactory;

    protected function casts(): array
    {
        return [
            'status' => PostRevisionStatus::class,
            'submitted_at' => 'datetime',
            'reviewed_at' => 'datetime',
            'approved_at' => 'datetime',
        ];
    }

    public function post(): BelongsTo
    {
        return $this->belongsTo(Post::class);
    }

    public function municipality(): BelongsTo
    {
        return $this->belongsTo(Municipality::class);
    }

    public function category(): BelongsTo
    {
        return $this->belongsTo(PostCategory::class, 'category_id');
    }

    public function creator(): BelongsTo
    {
        return $this->belongsTo(User::class, 'created_by');
    }

    public function reviewer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }

    public function attachments(): HasMany
    {
        return $this->hasMany(PostAttachment::class);
    }

    public function isPublishedSnapshot(): bool
    {
        return $this->status === PostRevisionStatus::Approved
            && $this->post?->current_published_revision_id === $this->id;
    }
}
