<?php

namespace Tests\Smoke;

use App\Domains\Municipality\Models\Municipality;
use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Services\AddGroupMemberService;
use App\Domains\Neighborhoods\Services\AssignPresidentService;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

/**
 * Smoke integral HTTP (kernel JSON). Ejecutar solo con phpunit.mysql.xml.
 * Al alternar usuarios Bearer, llamar {@see self::forgetBearerState()} (ver MobileAuthTest).
 */
class MembershipHttpFlowSmokeTest extends TestCase
{
    use CreatesPostFixtures;
    use RefreshDatabase;

    private const TESTING_DATABASE = 'red_vecinal_testing';

    protected function setUp(): void
    {
        parent::setUp();

        if (DB::connection()->getDriverName() !== 'mysql') {
            $this->markTestSkipped('Smoke HTTP requiere MySQL (phpunit.mysql.xml).');
        }

        $database = (string) config('database.connections.mysql.database');
        if ($database !== self::TESTING_DATABASE) {
            $this->markTestSkipped('Base activa no es '.self::TESTING_DATABASE.'.');
        }

        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seedPostsBasics();
    }

    public function test_membership_flow_vecino_to_president_via_http(): void
    {
        $municipality = Municipality::factory()->create();
        $anchor = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id]);
        $target = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id]);
        $vecinoPassword = 'smoke-password-not-logged';
        $vecino = User::factory()->create([
            'email' => 'smoke-vecino-'.uniqid('', true).'@red-vecinal.test',
            'password' => Hash::make($vecinoPassword),
        ]);
        $this->addMemberToGroup($anchor, $vecino);
        $president = $this->makePresidentFor($target);

        $vecinoToken = $this->loginBearer($vecino->email, $vecinoPassword);

        $requestId = $this->withToken($vecinoToken)
            ->postJson("/api/v1/groups/{$target->id}/membership-requests", [
                'request_note' => 'Smoke E2E',
            ])
            ->assertCreated()
            ->json('data.id');

        $presidentToken = $this->loginBearer($president->email, 'password');

        $this->forgetBearerState();
        $this->withToken($presidentToken)
            ->getJson('/api/v1/me')
            ->assertOk()
            ->assertJsonPath('id', $president->id);

        $this->forgetBearerState();
        $this->withToken($presidentToken)
            ->getJson('/api/v1/me/reviewable-groups')
            ->assertOk()
            ->assertJsonFragment(['id' => $target->id]);

        $this->forgetBearerState();
        $this->withToken($presidentToken)
            ->getJson("/api/v1/groups/{$target->id}/membership-requests?status=pending")
            ->assertOk()
            ->assertJsonCount(1, 'data');

        $this->forgetBearerState();
        $this->withToken($presidentToken)
            ->postJson("/api/v1/membership-requests/{$requestId}/approve", [
                'review_note' => 'Smoke OK',
            ])
            ->assertOk()
            ->assertJsonPath('data.status', 'approved');

        $this->forgetBearerState();
        $this->withToken($vecinoToken)
            ->getJson('/api/v1/me/membership-requests')
            ->assertOk()
            ->assertJsonFragment(['id' => $requestId, 'status' => 'approved']);

        $this->forgetBearerState();
        $this->withToken($vecinoToken)
            ->getJson('/api/v1/me/groups')
            ->assertOk()
            ->assertJsonFragment(['id' => $target->id]);
    }

    public function test_reject_cooldown_cancel_and_permissions(): void
    {
        $municipality = Municipality::factory()->create();
        $anchor = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id]);
        $target = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id]);
        $vecino = User::factory()->create();
        $this->addMemberToGroup($anchor, $vecino);
        $president = $this->makePresidentFor($target);
        $vecinoToken = $this->loginBearer($vecino->email, 'password');
        $presidentToken = $this->loginBearer($president->email, 'password');

        $this->forgetBearerState();
        $requestId = $this->withToken($vecinoToken)
            ->postJson("/api/v1/groups/{$target->id}/membership-requests")
            ->assertCreated()
            ->json('data.id');

        $this->forgetBearerState();
        $this->withToken($presidentToken)
            ->postJson("/api/v1/membership-requests/{$requestId}/reject")
            ->assertOk()
            ->assertJsonPath('data.status', 'rejected');

        $this->forgetBearerState();
        $this->withToken($vecinoToken)
            ->postJson("/api/v1/groups/{$target->id}/membership-requests")
            ->assertStatus(422);

        $targetB = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id]);
        $this->assignPresident($targetB, $president);

        $this->forgetBearerState();
        $cancelId = $this->withToken($vecinoToken)
            ->postJson("/api/v1/groups/{$targetB->id}/membership-requests")
            ->assertCreated()
            ->json('data.id');
        $this->withToken($vecinoToken)
            ->deleteJson("/api/v1/me/membership-requests/{$cancelId}")
            ->assertNoContent();

        $this->forgetBearerState();
        $this->withToken($presidentToken)
            ->postJson("/api/v1/membership-requests/{$cancelId}/approve")
            ->assertStatus(409);

        $municipalityB = Municipality::factory()->create();
        $groupForeign = NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityB->id]);
        $presidentAnchor = $this->makePresidentFor($anchor);
        $presidentAnchorToken = $this->loginBearer($presidentAnchor->email, 'password');

        $this->forgetBearerState();
        $this->withToken($presidentAnchorToken)
            ->getJson("/api/v1/groups/{$groupForeign->id}/membership-requests")
            ->assertForbidden();

        $moderator = User::factory()->create();
        $this->addMemberToGroup($target, $moderator, MembershipRole::Moderator);
        $targetC = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id]);
        $this->forgetBearerState();
        $modRequestId = $this->withToken($vecinoToken)
            ->postJson("/api/v1/groups/{$targetC->id}/membership-requests")
            ->assertCreated()
            ->json('data.id');
        $moderatorToken = $this->loginBearer($moderator->email, 'password');
        $this->forgetBearerState();
        $this->withToken($moderatorToken)
            ->postJson("/api/v1/membership-requests/{$modRequestId}/approve")
            ->assertForbidden();
    }

    private function loginBearer(string $email, string $password): string
    {
        $this->forgetBearerState();
        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $email,
            'password' => $password,
            'device_name' => 'smoke',
        ]);
        $response->assertOk();
        $token = (string) $response->json('token');
        $this->assertNotSame('', $token);

        return $token;
    }

    private function forgetBearerState(): void
    {
        $this->withoutToken();
        $this->app['auth']->forgetGuards();
    }

    private function makePresidentFor(NeighborhoodGroup $group): User
    {
        $president = User::factory()->create();
        $this->assignPresident($group, $president);

        return $president;
    }

    private function assignPresident(NeighborhoodGroup $group, User $president): void
    {
        $admin = User::factory()->create();
        app(AddGroupMemberService::class)->execute($group, $president, $admin, MembershipStatus::Active);
        app(AssignPresidentService::class)->execute($group, $president, $admin);
    }
}
