<?php

namespace Database\Factories;

use App\Domains\Municipality\Enums\MunicipalityMemberRole;
use App\Domains\Municipality\Enums\MunicipalityMemberStatus;
use App\Domains\Municipality\Models\Municipality;
use App\Domains\Municipality\Models\MunicipalityMember;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<MunicipalityMember>
 */
class MunicipalityMemberFactory extends Factory
{
    protected $model = MunicipalityMember::class;

    public function definition(): array
    {
        return [
            'municipality_id' => Municipality::factory(),
            'user_id' => User::factory(),
            'role' => MunicipalityMemberRole::Administrador,
            'status' => MunicipalityMemberStatus::Active,
        ];
    }
}
