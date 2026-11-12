<?php

namespace Database\Factories;

use App\Domains\Neighborhoods\Enums\MembershipRequestStatus;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Models\NeighborhoodMembershipRequest;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<NeighborhoodMembershipRequest>
 */
class NeighborhoodMembershipRequestFactory extends Factory
{
    protected $model = NeighborhoodMembershipRequest::class;

    public function definition(): array
    {
        return [
            'municipality_id' => 1,
            'neighborhood_group_id' => 1,
            'user_id' => User::factory(),
            'status' => MembershipRequestStatus::Pending,
        ];
    }

    public function forGroupAndUser(NeighborhoodGroup $group, User $user): static
    {
        return $this->state(fn () => [
            'neighborhood_group_id' => $group->id,
            'municipality_id' => $group->municipality_id,
            'user_id' => $user->id,
        ]);
    }
}
