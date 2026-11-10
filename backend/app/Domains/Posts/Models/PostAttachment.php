<?php

namespace App\Domains\Posts\Models;

use App\Models\User;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\SoftDeletes;

#[Fillable([
    'post_revision_id',
    'post_id',
    'municipality_id',
    'uploaded_by',
    'disk',
    'path',
    'original_display_name',
    'mime_type',
    'size_bytes',
    'checksum',
])]
class PostAttachment extends Model
{
    use SoftDeletes;

    public function revision(): BelongsTo
    {
        return $this->belongsTo(PostRevision::class, 'post_revision_id');
    }

    public function post(): BelongsTo
    {
        return $this->belongsTo(Post::class);
    }

    public function uploader(): BelongsTo
    {
        return $this->belongsTo(User::class, 'uploaded_by');
    }
}
