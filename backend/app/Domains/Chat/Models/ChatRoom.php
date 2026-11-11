<?php

namespace App\Domains\Chat\Models;

use App\Domains\Chat\Enums\ChatRoomStatus;
use App\Domains\Chat\Enums\ChatRoomType;
use App\Domains\Municipality\Models\Municipality;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable([
    'municipality_id',
    'neighborhood_group_id',
    'type',
    'status',
])]
class ChatRoom extends Model
{
    protected function casts(): array
    {
        return [
            'type' => ChatRoomType::class,
            'status' => ChatRoomStatus::class,
        ];
    }

    public function municipality(): BelongsTo
    {
        return $this->belongsTo(Municipality::class);
    }

    public function neighborhoodGroup(): BelongsTo
    {
        return $this->belongsTo(NeighborhoodGroup::class);
    }

    public function messages(): HasMany
    {
        return $this->hasMany(ChatMessage::class);
    }

    public function isWritable(): bool
    {
        return $this->status === ChatRoomStatus::Active
            && $this->neighborhoodGroup?->isAdministrable();
    }
}
