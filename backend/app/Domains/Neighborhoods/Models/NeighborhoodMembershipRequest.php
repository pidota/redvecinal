<?php

namespace App\Domains\Neighborhoods\Models;

use App\Domains\Municipality\Models\Municipality;
use App\Domains\Neighborhoods\Enums\MembershipRequestStatus;
use App\Models\User;
use Database\Factories\NeighborhoodMembershipRequestFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\UseFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'municipality_id',
    'neighborhood_group_id',
    'user_id',
    'status',
    'request_note',
    'review_note',
    'reviewed_by',
    'reviewed_at',
    'rejected_at',
    'cancelled_at',
])]
#[UseFactory(NeighborhoodMembershipRequestFactory::class)]
class NeighborhoodMembershipRequest extends Model
{
    use HasFactory;

    protected static function booted(): void
    {
        static::saving(function (self $request): void {
            if ($request->getConnection()->getDriverName() === 'mysql') {
                return;
            }

            $request->pending_slot = $request->status === MembershipRequestStatus::Pending ? 1 : null;
        });
    }

    protected function casts(): array
    {
        return [
            'status' => MembershipRequestStatus::class,
            'reviewed_at' => 'datetime',
            'rejected_at' => 'datetime',
            'cancelled_at' => 'datetime',
        ];
    }

    public function neighborhoodGroup(): BelongsTo
    {
        return $this->belongsTo(NeighborhoodGroup::class, 'neighborhood_group_id');
    }

    public function municipality(): BelongsTo
    {
        return $this->belongsTo(Municipality::class);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function reviewer(): BelongsTo
    {
        return $this->belongsTo(User::class, 'reviewed_by');
    }

    public function isPending(): bool
    {
        return $this->status === MembershipRequestStatus::Pending;
    }
}
