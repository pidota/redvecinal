<?php

namespace Tests\Feature\Neighborhoods;

use App\Domains\Neighborhoods\Enums\MembershipRequestStatus;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Models\NeighborhoodMembershipRequest;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Tests\TestCase;

class MembershipRequestMysqlConstraintTest extends TestCase
{
    use RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();

        if (DB::connection()->getDriverName() !== 'mysql') {
            $this->markTestSkipped('Requiere conexión MySQL para validar pending_slot generado.');
        }

        $this->seed(RolesAndPermissionsSeeder::class);
    }

    public function test_unique_pending_slot_rejects_parallel_pending_rows(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $user = User::factory()->create();

        NeighborhoodMembershipRequest::query()->create([
            'municipality_id' => $group->municipality_id,
            'neighborhood_group_id' => $group->id,
            'user_id' => $user->id,
            'status' => MembershipRequestStatus::Pending,
            'request_note' => null,
        ]);

        $this->expectException(QueryException::class);

        NeighborhoodMembershipRequest::query()->create([
            'municipality_id' => $group->municipality_id,
            'neighborhood_group_id' => $group->id,
            'user_id' => $user->id,
            'status' => MembershipRequestStatus::Pending,
            'request_note' => null,
        ]);
    }

    public function test_resolved_requests_keep_history(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $user = User::factory()->create();

        $first = NeighborhoodMembershipRequest::query()->create([
            'municipality_id' => $group->municipality_id,
            'neighborhood_group_id' => $group->id,
            'user_id' => $user->id,
            'status' => MembershipRequestStatus::Rejected,
            'rejected_at' => now()->subDays(10),
        ]);

        $second = NeighborhoodMembershipRequest::query()->create([
            'municipality_id' => $group->municipality_id,
            'neighborhood_group_id' => $group->id,
            'user_id' => $user->id,
            'status' => MembershipRequestStatus::Pending,
        ]);

        $this->assertNotEquals($first->id, $second->id);
        $this->assertSame(2, NeighborhoodMembershipRequest::query()->where('user_id', $user->id)->count());
    }
}
