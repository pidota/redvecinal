<?php

namespace App\Domains\Neighborhoods\Models;

use App\Domains\Municipality\Models\Municipality;
use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Models\User;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Database\Factories\GroupMemberFactory;
use Illuminate\Database\Eloquent\Attributes\UseFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

#[Fillable([
    'municipality_id',
    'neighborhood_group_id',
    'user_id',
    'membership_role',
    'status',
    'approved_by',
    'approved_at',
    'joined_at',
])]
#[UseFactory(GroupMemberFactory::class)]
class GroupMember extends Model
{
    use HasFactory;
    protected function casts(): array
    {
        return [
            'membership_role' => MembershipRole::class,
            'status' => MembershipStatus::class,
            'approved_at' => 'datetime',
            'joined_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function neighborhoodGroup(): BelongsTo
    {
        return $this->belongsTo(NeighborhoodGroup::class, 'neighborhood_group_id');
    }

    public function municipality(): BelongsTo
    {
        return $this->belongsTo(Municipality::class);
    }

    public function approver(): BelongsTo
    {
        return $this->belongsTo(User::class, 'approved_by');
    }

    public function events(): HasMany
    {
        return $this->hasMany(GroupMembershipEvent::class, 'group_member_id');
    }

    public function canPerformGroupAdministration(): bool
    {
        if ($this->status !== MembershipStatus::Active) {
            return false;
        }

        return in_array($this->membership_role, [MembershipRole::President, MembershipRole::Moderator], true);
    }
}
