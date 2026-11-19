<?php

namespace App\Domains\Posts\Models;

use App\Domains\Municipality\Models\Municipality;
use App\Domains\Posts\Enums\PostReportStatus;
use App\Models\User;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'post_id',
    'post_comment_id',
    'municipality_id',
    'reporter_id',
    'reason_code',
    'details',
    'status',
    'resolved_by',
    'resolved_at',
    'resolution_note',
])]
class PostReport extends Model
{
    protected function casts(): array
    {
        return [
            'status' => PostReportStatus::class,
            'resolved_at' => 'datetime',
        ];
    }

    public static function labelForReasonCode(?string $code): string
    {
        return match ($code) {
            'spam' => 'Spam o publicidad no deseada',
            'inappropriate' => 'Contenido inapropiado',
            default => (string) $code,
        };
    }

    public function post(): BelongsTo
    {
        return $this->belongsTo(Post::class)->withTrashed();
    }

    public function municipality(): BelongsTo
    {
        return $this->belongsTo(Municipality::class);
    }

    public function comment(): BelongsTo
    {
        return $this->belongsTo(PostComment::class, 'post_comment_id');
    }

    public function reporter(): BelongsTo
    {
        return $this->belongsTo(User::class, 'reporter_id');
    }

    public function resolver(): BelongsTo
    {
        return $this->belongsTo(User::class, 'resolved_by');
    }
}
