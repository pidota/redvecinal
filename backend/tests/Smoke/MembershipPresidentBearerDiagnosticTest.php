<?php

namespace Tests\Smoke;

use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Policies\NeighborhoodMembershipRequestPolicy;
use App\Domains\Neighborhoods\Support\ReviewableNeighborhoodGroupsQuery;
use App\Domains\Municipality\Models\Municipality;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Services\AddGroupMemberService;
use App\Domains\Neighborhoods\Services\AssignPresidentService;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Laravel\Sanctum\PersonalAccessToken;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

/**
 * Diagnóstico Bearer vs guard (solo red_vecinal_testing).
 */
class MembershipPresidentBearerDiagnosticTest extends TestCase
{
    use CreatesPostFixtures;
    use RefreshDatabase;

    private const TESTING_DATABASE = 'red_vecinal_testing';

    protected function setUp(): void
    {
        parent::setUp();

        if (DB::connection()->getDriverName() !== 'mysql') {
            $this->markTestSkipped('Diagnóstico requiere MySQL (phpunit.mysql.xml).');
        }

        if ((string) config('database.connections.mysql.database') !== self::TESTING_DATABASE) {
            $this->markTestSkipped('Base activa no es '.self::TESTING_DATABASE.'.');
        }

        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seedPostsBasics();
    }

    public function test_president_bearer_authentication_diagnostic(): void
    {
        [$target, $president, $vecino, $requestId] = $this->seedPendingScenario();

        $vecinoToken = $this->loginBearer($vecino, 'password');
        $this->withToken($vecinoToken)->getJson('/api/v1/me')->assertJsonPath('id', $vecino->id);

        $presidentToken = $this->loginBearer($president, 'password');

        $meStaleGuard = $this->withToken($presidentToken)->getJson('/api/v1/me');
        $reviewableStaleGuard = $this->withToken($presidentToken)->getJson('/api/v1/me/reviewable-groups');

        $this->forgetBearerState();
        $me = $this->withToken($presidentToken)->getJson('/api/v1/me');
        $reviewable = $this->withToken($presidentToken)->getJson('/api/v1/me/reviewable-groups');
        $pending = $this->withToken($presidentToken)
            ->getJson("/api/v1/groups/{$target->id}/membership-requests?status=pending");

        $this->emitDiagnostics([
            'president_id' => $president->id,
            'vecino_id' => $vecino->id,
            'group_id' => $target->id,
            'request_id' => $requestId,
            'me_stale_guard_user_id' => $meStaleGuard->json('id'),
            'reviewable_stale_guard_count' => count($reviewableStaleGuard->json('data') ?? []),
            'me_status' => $me->status(),
            'me_user_id' => $me->json('id'),
            'reviewable_status' => $reviewable->status(),
            'reviewable_ids' => collect($reviewable->json('data'))->pluck('id')->all(),
            'pending_status' => $pending->status(),
            'pending_count' => count($pending->json('data') ?? []),
            'token_abilities' => $this->tokenAbilitiesSummary($presidentToken),
            'policy_can_review' => app(NeighborhoodMembershipRequestPolicy::class)
                ->canReviewMembershipRequests($president->fresh(), $target->fresh()),
            'query_reviewable_ids' => ReviewableNeighborhoodGroupsQuery::forUser($president->fresh())
                ->pluck('id')
                ->all(),
            'president_membership_role' => GroupMember::query()
                ->where('neighborhood_group_id', $target->id)
                ->where('user_id', $president->id)
                ->value('membership_role')?->value,
            'president_membership_status' => GroupMember::query()
                ->where('neighborhood_group_id', $target->id)
                ->where('user_id', $president->id)
                ->value('status')?->value,
        ]);

        $me->assertOk()->assertJsonPath('id', $president->id);
        $reviewable->assertOk();
        $this->assertContains($target->id, collect($reviewable->json('data'))->pluck('id')->all());
        $pending->assertOk()->assertJsonCount(1, 'data');
    }

    public function test_original_smoke_sequence_without_forget_guards_before_president_calls(): void
    {
        $municipality = Municipality::factory()->create();
        $anchor = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id]);
        $target = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id]);
        $vecinoPassword = 'smoke-password-not-logged';
        $vecino = User::factory()->create([
            'email' => 'smoke-vecino-'.uniqid('', true).'@red-vecinal.test',
            'password' => \Illuminate\Support\Facades\Hash::make($vecinoPassword),
        ]);
        $this->addMemberToGroup($anchor, $vecino);
        $president = User::factory()->create();
        $admin = User::factory()->create();
        app(AddGroupMemberService::class)->execute($target, $president, $admin, MembershipStatus::Active);
        app(AssignPresidentService::class)->execute($target, $president, $admin);

        $loginVecino = $this->postJson('/api/v1/auth/login', [
            'email' => $vecino->email,
            'password' => $vecinoPassword,
            'device_name' => 'smoke',
        ]);
        $loginVecino->assertOk();
        $vecinoToken = (string) $loginVecino->json('token');

        $this->withToken($vecinoToken)
            ->postJson("/api/v1/groups/{$target->id}/membership-requests", ['request_note' => 'Smoke'])
            ->assertCreated();

        $loginPresident = $this->postJson('/api/v1/auth/login', [
            'email' => $president->email,
            'password' => 'password',
            'device_name' => 'smoke',
        ]);
        $loginPresident->assertOk();
        $presidentToken = (string) $loginPresident->json('token');

        $reviewable = $this->withToken($presidentToken)->getJson('/api/v1/me/reviewable-groups');
        $me = $this->withToken($presidentToken)->getJson('/api/v1/me');

        $this->emitDiagnostics([
            'me_user_id' => $me->json('id'),
            'president_id' => $president->id,
            'vecino_id' => $vecino->id,
            'reviewable_count' => count($reviewable->json('data') ?? []),
            'reviewable_total' => $reviewable->json('meta.total'),
        ]);

        $this->forgetBearerState();
        $reviewableAfterFlush = $this->withToken($presidentToken)->getJson('/api/v1/me/reviewable-groups');

        $this->assertSame($vecino->id, $me->json('id'), 'Sin forgetGuards el guard sigue como el usuario Bearer anterior.');
        $this->assertSame(0, (int) $reviewable->json('meta.total'));

        $reviewableAfterFlush->assertOk();
        $this->assertContains($target->id, collect($reviewableAfterFlush->json('data'))->pluck('id')->all());
        $this->forgetBearerState();
        $this->withToken($presidentToken)->getJson('/api/v1/me')->assertJsonPath('id', $president->id);
    }

    /**
     * @return array{0: NeighborhoodGroup, 1: User, 2: User, 3: int}
     */
    private function seedPendingScenario(): array
    {
        $municipality = Municipality::factory()->create();
        $anchor = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id]);
        $target = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id]);
        $vecino = User::factory()->create();
        $this->addMemberToGroup($anchor, $vecino);
        $president = User::factory()->create();
        $admin = User::factory()->create();
        app(AddGroupMemberService::class)->execute($target, $president, $admin, MembershipStatus::Active);
        app(AssignPresidentService::class)->execute($target, $president, $admin);

        $this->forgetBearerState();
        $vecinoToken = $this->loginBearer($vecino, 'password');
        $requestId = $this->withToken($vecinoToken)
            ->postJson("/api/v1/groups/{$target->id}/membership-requests", ['request_note' => 'diag'])
            ->assertCreated()
            ->json('data.id');

        return [$target, $president, $vecino, $requestId];
    }

    private function loginBearer(User $user, string $password): string
    {
        $this->forgetBearerState();
        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => $password,
            'device_name' => 'bearer-diag',
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

    /**
     * @return list<string>
     */
    private function tokenAbilitiesSummary(string $plainToken): array
    {
        $access = PersonalAccessToken::findToken($plainToken);

        return $access !== null ? $access->abilities : [];
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    private function emitDiagnostics(array $payload): void
    {
        fwrite(STDERR, "membership_bearer_diagnostic: ".json_encode($payload, JSON_THROW_ON_ERROR)."\n");
    }
}
