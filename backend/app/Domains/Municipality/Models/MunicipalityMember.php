<?php

namespace App\Domains\Municipality\Models;

use App\Domains\Municipality\Enums\MunicipalityMemberRole;
use App\Domains\Municipality\Enums\MunicipalityMemberStatus;
use App\Models\User;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Database\Factories\MunicipalityMemberFactory;
use Illuminate\Database\Eloquent\Attributes\UseFactory;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

#[Fillable([
    'municipality_id',
    'user_id',
    'role',
    'status',
])]
#[UseFactory(MunicipalityMemberFactory::class)]
class MunicipalityMember extends Model
{
    use HasFactory;
    protected function casts(): array
    {
        return [
            'role' => MunicipalityMemberRole::class,
            'status' => MunicipalityMemberStatus::class,
        ];
    }

    public function municipality(): BelongsTo
    {
        return $this->belongsTo(Municipality::class);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function isActiveAdministrador(): bool
    {
        return $this->status === MunicipalityMemberStatus::Active
            && $this->role === MunicipalityMemberRole::Administrador;
    }
}
