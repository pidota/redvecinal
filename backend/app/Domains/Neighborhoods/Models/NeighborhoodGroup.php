<?php

namespace App\Domains\Neighborhoods\Models;

use App\Domains\Municipality\Models\Municipality;
use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Enums\NeighborhoodGroupStatus;
use App\Models\User;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Database\Factories\NeighborhoodGroupFactory;
use Illuminate\Database\Eloquent\Attributes\UseFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Database\Eloquent\SoftDeletes;

#[Fillable([
    'municipality_id',
    'name',
    'slug',
    'registration_number',
    'description',
    'address',
    'contact_email',
    'contact_phone',
    'status',
    'settings',
])]
#[UseFactory(NeighborhoodGroupFactory::class)]
class NeighborhoodGroup extends Model
{
    use HasFactory, SoftDeletes;

    protected function casts(): array
    {
        return [
            'settings' => 'array',
            'status' => NeighborhoodGroupStatus::class,
        ];
    }

    public function municipality(): BelongsTo
    {
        return $this->belongsTo(Municipality::class);
    }

    public function memberships(): HasMany
    {
        return $this->hasMany(GroupMember::class, 'neighborhood_group_id');
    }

    public function membershipRequests(): HasMany
    {
        return $this->hasMany(NeighborhoodMembershipRequest::class, 'neighborhood_group_id');
    }

    public function users(): BelongsToMany
    {
        return $this->belongsToMany(User::class, 'group_members', 'neighborhood_group_id', 'user_id')
            ->withPivot(['membership_role', 'status', 'municipality_id', 'approved_at', 'joined_at'])
            ->withTimestamps();
    }

    public function activeMembers(): HasMany
    {
        return $this->memberships()->where('status', MembershipStatus::Active);
    }

    public function presidentMembership(): HasOne
    {
        return $this->hasOne(GroupMember::class, 'neighborhood_group_id')
            ->where('membership_role', MembershipRole::President)
            ->where('status', MembershipStatus::Active);
    }

    public function isAdministrable(): bool
    {
        return $this->status === NeighborhoodGroupStatus::Active;
    }
}
