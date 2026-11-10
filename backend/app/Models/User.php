<?php

namespace App\Models;

// use Illuminate\Contracts\Auth\MustVerifyEmail;
use App\Domains\Municipality\Enums\MunicipalityMemberStatus;
use App\Domains\Municipality\Models\MunicipalityMember;
use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use Database\Factories\UserFactory;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Filament\Models\Contracts\FilamentUser;
use Filament\Panel;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\Hidden;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;
use Laravel\Sanctum\HasApiTokens;
use Spatie\Permission\Traits\HasRoles;

#[Fillable(['name', 'email', 'password'])]
#[Hidden(['password', 'remember_token'])]
class User extends Authenticatable implements FilamentUser
{
    /** @use HasFactory<UserFactory> */
    use HasApiTokens, HasFactory, HasRoles, Notifiable;

    /**
     * Get the attributes that should be cast.
     *
     * @return array<string, string>
     */
    protected function casts(): array
    {
        return [
            'email_verified_at' => 'datetime',
            'password' => 'hashed',
        ];
    }

    public function canAccessPanel(Panel $panel): bool
    {
        if ($panel->getId() !== 'admin') {
            return false;
        }

        $allowedRoles = config('red_vecinal.filament_panel_roles', []);

        if ($allowedRoles === []) {
            return false;
        }

        return $this->hasAnyRole($allowedRoles);
    }

    public function groupMemberships(): HasMany
    {
        return $this->hasMany(GroupMember::class);
    }

    public function neighborhoodGroups(): BelongsToMany
    {
        return $this->belongsToMany(NeighborhoodGroup::class, 'group_members', 'user_id', 'neighborhood_group_id')
            ->withPivot(['membership_role', 'status', 'municipality_id'])
            ->withTimestamps();
    }

    public function municipalityMemberships(): HasMany
    {
        return $this->hasMany(MunicipalityMember::class);
    }

    public function activeMunicipalityMemberships(): HasMany
    {
        return $this->municipalityMemberships()
            ->where('status', MunicipalityMemberStatus::Active);
    }

    public function activeGroupMembershipFor(NeighborhoodGroup $group): ?GroupMember
    {
        return $this->groupMemberships()
            ->where('neighborhood_group_id', $group->id)
            ->where('status', MembershipStatus::Active)
            ->first();
    }

    public function isActivePresidentOf(NeighborhoodGroup $group): bool
    {
        $membership = $this->activeGroupMembershipFor($group);

        return $membership?->membership_role === MembershipRole::President;
    }

    public function isSuperAdmin(): bool
    {
        return $this->hasRole('super-admin');
    }

    public function isMunicipalAdministratorFor(int $municipalityId): bool
    {
        if (! $this->hasRole('administrador-municipal')) {
            return false;
        }

        return $this->municipalityMemberships()
            ->where('municipality_id', $municipalityId)
            ->where('status', MunicipalityMemberStatus::Active)
            ->where('role', \App\Domains\Municipality\Enums\MunicipalityMemberRole::Administrador)
            ->exists();
    }
}
