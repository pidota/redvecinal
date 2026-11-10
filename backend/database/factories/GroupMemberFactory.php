<?php

namespace Database\Factories;

use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<GroupMember>
 */
class GroupMemberFactory extends Factory
{
    protected $model = GroupMember::class;

    public function definition(): array
    {
        $group = NeighborhoodGroup::factory()->create();

        return [
            'municipality_id' => $group->municipality_id,
            'neighborhood_group_id' => $group->id,
            'user_id' => User::factory(),
            'membership_role' => MembershipRole::Member,
            'status' => MembershipStatus::Active,
            'joined_at' => now(),
        ];
    }

    public function president(): static
    {
        return $this->state(fn () => [
            'membership_role' => MembershipRole::President,
        ]);
    }

    public function pending(): static
    {
        return $this->state(fn () => [
            'status' => MembershipStatus::Pending,
            'joined_at' => null,
        ]);
    }
}
