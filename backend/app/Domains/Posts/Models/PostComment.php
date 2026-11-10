<?php

namespace App\Domains\Posts\Models;

use App\Domains\Posts\Enums\PostCommentStatus;
use App\Models\User;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

#[Fillable([
    'post_id',
    'municipality_id',
    'author_id',
    'body',
    'status',
    'hidden_by',
    'hidden_at',
    'hide_reason',
])]
class PostComment extends Model
{
    use SoftDeletes;

    protected function casts(): array
    {
        return [
            'status' => PostCommentStatus::class,
            'hidden_at' => 'datetime',
        ];
    }

    public function post(): BelongsTo
    {
        return $this->belongsTo(Post::class);
    }

    public function author(): BelongsTo
    {
        return $this->belongsTo(User::class, 'author_id');
    }
}
