<?php

namespace App\Domains\Chat\Models;

use App\Domains\Chat\Enums\ChatMessageReportStatus;
use App\Models\User;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'municipality_id',
    'chat_message_id',
    'reporter_id',
    'reason_code',
    'details',
    'status',
    'reviewed_by',
    'reviewed_at',
    'resolution_note',
])]
class ChatMessageReport extends Model
{
    protected function casts(): array
    {
        return [
            'status' => ChatMessageReportStatus::class,
            'reviewed_at' => 'datetime',
        ];
    }

    public function message(): BelongsTo
    {
        return $this->belongsTo(ChatMessage::class, 'chat_message_id');
    }

    public function reporter(): BelongsTo
    {
        return $this->belongsTo(User::class, 'reporter_id');
    }

    public function reviewer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }
}
