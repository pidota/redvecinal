<?php

namespace App\Domains\Chat\Models;

use App\Domains\Chat\Enums\ChatMessageStatus;
use App\Models\User;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable([
    'municipality_id',
    'chat_room_id',
    'sender_id',
    'body',
    'status',
    'client_message_id',
    'version',
    'edited_at',
    'deleted_at',
])]
class ChatMessage extends Model
{
    protected function casts(): array
    {
        return [
            'status' => ChatMessageStatus::class,
            'edited_at' => 'datetime',
            'deleted_at' => 'datetime',
        ];
    }

    public function room(): BelongsTo
    {
        return $this->belongsTo(ChatRoom::class, 'chat_room_id');
    }

    public function sender(): BelongsTo
    {
        return $this->belongsTo(User::class, 'sender_id');
    }

    public function reports(): HasMany
    {
        return $this->hasMany(ChatMessageReport::class);
    }

    public function isVisibleToMembers(): bool
    {
        return $this->status === ChatMessageStatus::Visible;
    }
}
