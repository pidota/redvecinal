<?php

namespace Tests\Feature\Auth;

use App\Domains\Municipality\Enums\MunicipalityMemberRole;
use App\Domains\Municipality\Enums\MunicipalityMemberStatus;
use App\Domains\Municipality\Models\Municipality;
use App\Domains\Municipality\Models\MunicipalityMember;
use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Facades\RateLimiter;
use Laravel\Sanctum\PersonalAccessToken;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class MobileAuthTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_valid_login_returns_token_and_user(): void
    {
        [$group, $vecino] = $this->vecinoWithGroup();
        $password = 'secret-password';

        $vecino->forceFill(['password' => Hash::make($password)])->save();

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $vecino->email,
            'password' => $password,
            'device_name' => 'flutter-test',
        ]);

        $response->assertOk()
            ->assertJsonStructure(['token', 'token_type', 'user' => ['id', 'name', 'email', 'municipality_memberships']])
            ->assertJsonPath('token_type', 'Bearer')
            ->assertJsonPath('user.id', $vecino->id);
    }

    public function test_wrong_password_returns_uniform_unauthorized(): void
    {
        [$group, $vecino] = $this->vecinoWithGroup();

        $this->postJson('/api/v1/auth/login', [
            'email' => $vecino->email,
            'password' => 'wrong',
            'device_name' => 'device',
        ])
            ->assertUnauthorized()
            ->assertJsonPath('message', 'Las credenciales proporcionadas no son correctas.');
    }

    public function test_unknown_user_returns_same_message_as_wrong_password(): void
    {
        $this->postJson('/api/v1/auth/login', [
            'email' => 'nobody@example.com',
            'password' => 'wrong',
            'device_name' => 'device',
        ])
            ->assertUnauthorized()
            ->assertJsonPath('message', 'Las credenciales proporcionadas no son correctas.');
    }

    public function test_email_validation_errors(): void
    {
        $this->postJson('/api/v1/auth/login', [
            'email' => 'not-an-email',
            'password' => 'x',
            'device_name' => 'device',
        ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['email']);
    }

    public function test_device_name_is_required(): void
    {
        $user = User::factory()->create();

        $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => 'password',
        ])
            ->assertUnprocessable()
            ->assertJsonValidationErrors(['device_name']);
    }

    public function test_login_rate_limiting(): void
    {
        $user = User::factory()->create();

        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/api/v1/auth/login', [
                'email' => $user->email,
                'password' => 'bad',
                'device_name' => 'device',
            ])->assertUnauthorized();
        }

        $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => 'bad',
            'device_name' => 'device',
        ])->assertStatus(429);
    }

    public function test_me_requires_authentication(): void
    {
        $this->getJson('/api/v1/me')->assertUnauthorized();
    }

    public function test_me_returns_authenticated_profile(): void
    {
        [$group, $vecino] = $this->vecinoWithGroup();
        $token = $vecino->createToken('device')->plainTextToken;

        $this->withToken($token)
            ->getJson('/api/v1/me')
            ->assertOk()
            ->assertJsonPath('id', $vecino->id)
            ->assertJsonPath('email', $vecino->email);
    }

    public function test_logout_revokes_only_current_token(): void
    {
        $vecino = User::factory()->create();
        $group = NeighborhoodGroup::factory()->create();
        $this->addMemberToGroup($group, $vecino);

        $tokenA = $vecino->createToken('phone-a')->plainTextToken;
        $tokenB = $vecino->createToken('phone-b')->plainTextToken;

        [$tokenAId] = explode('|', $tokenA, 2);

        $this->withToken($tokenA)->postJson('/api/v1/auth/logout')->assertNoContent();

        $this->assertDatabaseMissing('personal_access_tokens', ['id' => $tokenAId]);
        $this->assertNull(PersonalAccessToken::findToken($tokenA));

        $this->app['auth']->forgetGuards();

        $this->withToken($tokenA)->getJson('/api/v1/me')->assertUnauthorized();
        $this->withToken($tokenB)->getJson('/api/v1/me')->assertOk();
    }

    public function test_revoked_token_is_rejected(): void
    {
        $vecino = User::factory()->create();
        $group = NeighborhoodGroup::factory()->create();
        $this->addMemberToGroup($group, $vecino);

        $token = $vecino->createToken('device')->plainTextToken;
        $this->withToken($token)->postJson('/api/v1/auth/logout')->assertNoContent();
        $this->app['auth']->forgetGuards();
        $this->withToken($token)->getJson('/api/v1/me')->assertUnauthorized();
    }

    public function test_user_without_memberships_cannot_login(): void
    {
        $password = 'plain-password';
        $user = User::factory()->create([
            'password' => Hash::make($password),
        ]);

        $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => $password,
            'device_name' => 'nuevo',
        ])
            ->assertUnauthorized()
            ->assertJsonPath('message', 'Las credenciales proporcionadas no son correctas.');
    }

    public function test_user_with_multiple_municipality_memberships(): void
    {
        $password = 'pass-123';
        $user = User::factory()->create(['password' => Hash::make($password)]);
        $muniA = Municipality::factory()->create(['name' => 'Alpha']);
        $muniB = Municipality::factory()->create(['name' => 'Beta']);

        MunicipalityMember::factory()->create([
            'municipality_id' => $muniA->id,
            'user_id' => $user->id,
            'role' => MunicipalityMemberRole::Funcionario,
            'status' => MunicipalityMemberStatus::Active,
        ]);
        MunicipalityMember::factory()->create([
            'municipality_id' => $muniB->id,
            'user_id' => $user->id,
            'role' => MunicipalityMemberRole::Administrador,
            'status' => MunicipalityMemberStatus::Active,
        ]);

        $response = $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => $password,
            'device_name' => 'ipad',
        ])->assertOk();

        $memberships = $response->json('user.municipality_memberships');
        $this->assertCount(2, $memberships);
        $this->assertEqualsCanonicalizing(
            [$muniA->id, $muniB->id],
            collect($memberships)->pluck('municipality_id')->all()
        );
    }

    public function test_responses_do_not_leak_sensitive_fields(): void
    {
        $password = 'secret';
        $user = User::factory()->create(['password' => Hash::make($password)]);
        $group = NeighborhoodGroup::factory()->create();
        $this->addMemberToGroup($group, $user);

        $login = $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => $password,
            'device_name' => 'phone',
        ])->assertOk();

        $body = json_encode($login->json(), JSON_THROW_ON_ERROR);
        $this->assertStringNotContainsString('$2y$', $body);
        $this->assertStringNotContainsString('remember_token', $body);
        $login->assertJsonMissingPath('user.password');
    }

    public function test_only_suspended_group_memberships_cannot_login(): void
    {
        $password = 'secret';
        $user = User::factory()->create(['password' => Hash::make($password)]);
        $group = NeighborhoodGroup::factory()->create();

        GroupMember::factory()->create([
            'neighborhood_group_id' => $group->id,
            'municipality_id' => $group->municipality_id,
            'user_id' => $user->id,
            'membership_role' => MembershipRole::Member,
            'status' => MembershipStatus::Suspended,
        ]);

        $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => $password,
            'device_name' => 'phone',
        ])
            ->assertUnauthorized()
            ->assertJsonPath('message', 'Las credenciales proporcionadas no son correctas.');
    }

    public function test_login_normalizes_email_for_rate_limit_and_lookup(): void
    {
        $password = 'secret';
        $user = User::factory()->create([
            'email' => 'Vecino@Example.com',
            'password' => Hash::make($password),
        ]);
        $group = NeighborhoodGroup::factory()->create();
        $this->addMemberToGroup($group, $user);

        $this->postJson('/api/v1/auth/login', [
            'email' => '  VECINO@example.COM  ',
            'password' => $password,
            'device_name' => 'phone',
        ])->assertOk();
    }

    public function test_super_admin_can_login_without_group_or_municipality_membership(): void
    {
        $password = 'secret';
        $user = User::factory()->create(['password' => Hash::make($password)]);
        $user->assignRole('super-admin');

        $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => $password,
            'device_name' => 'admin-phone',
        ])->assertOk();
    }

    public function test_inactive_municipality_membership_without_active_group_cannot_login(): void
    {
        $password = 'secret';
        $user = User::factory()->create(['password' => Hash::make($password)]);
        $municipality = Municipality::factory()->create();

        MunicipalityMember::factory()->create([
            'municipality_id' => $municipality->id,
            'user_id' => $user->id,
            'role' => MunicipalityMemberRole::Funcionario,
            'status' => MunicipalityMemberStatus::Inactive,
        ]);

        $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => $password,
            'device_name' => 'phone',
        ])
            ->assertUnauthorized()
            ->assertJsonPath('message', 'Las credenciales proporcionadas no son correctas.');
    }

    public function test_active_group_member_can_login_despite_inactive_municipality_row(): void
    {
        $password = 'secret';
        $user = User::factory()->create(['password' => Hash::make($password)]);
        $group = NeighborhoodGroup::factory()->create();
        $this->addMemberToGroup($group, $user);

        MunicipalityMember::factory()->create([
            'municipality_id' => $group->municipality_id,
            'user_id' => $user->id,
            'role' => MunicipalityMemberRole::Funcionario,
            'status' => MunicipalityMemberStatus::Inactive,
        ]);

        $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => $password,
            'device_name' => 'phone',
        ])->assertOk();
    }

    public function test_expired_login_token_is_rejected(): void
    {
        [$group, $vecino] = $this->vecinoWithGroup();
        $plain = $vecino->createToken('device', ['*'], now()->subMinute())->plainTextToken;

        $this->app['auth']->forgetGuards();

        $this->withToken($plain)->getJson('/api/v1/me')->assertUnauthorized();
    }

    public function test_suspended_group_membership_after_login_blocks_group_show(): void
    {
        $password = 'secret';
        $user = User::factory()->create(['password' => Hash::make($password)]);
        $group = NeighborhoodGroup::factory()->create();
        $member = GroupMember::factory()->create([
            'neighborhood_group_id' => $group->id,
            'municipality_id' => $group->municipality_id,
            'user_id' => $user->id,
            'membership_role' => MembershipRole::Member,
            'status' => MembershipStatus::Active,
        ]);

        $token = $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => $password,
            'device_name' => 'phone',
        ])->assertOk()->json('token');

        $this->withToken($token)->getJson("/api/v1/groups/{$group->id}")->assertOk();

        $member->update(['status' => MembershipStatus::Suspended]);

        $this->app['auth']->forgetGuards();
        $this->withToken($token)->getJson("/api/v1/groups/{$group->id}")->assertForbidden();
    }

    public function test_me_omits_membership_after_municipal_membership_deactivated(): void
    {
        $password = 'secret';
        $user = User::factory()->create(['password' => Hash::make($password)]);
        $municipality = Municipality::factory()->create();

        $membership = MunicipalityMember::factory()->create([
            'municipality_id' => $municipality->id,
            'user_id' => $user->id,
            'role' => MunicipalityMemberRole::Funcionario,
            'status' => MunicipalityMemberStatus::Active,
        ]);

        $login = $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => $password,
            'device_name' => 'phone',
        ])->assertOk();

        $token = $login->json('token');
        $this->withToken($token)->getJson('/api/v1/me')->assertJsonCount(1, 'municipality_memberships');

        $membership->update(['status' => MunicipalityMemberStatus::Inactive]);

        $this->app['auth']->forgetGuards();
        $this->withToken($token)->getJson('/api/v1/me')->assertJsonPath('municipality_memberships', []);
    }

    public function test_login_and_me_user_contract_match(): void
    {
        $password = 'secret';
        $user = User::factory()->create(['password' => Hash::make($password)]);
        $municipality = Municipality::factory()->create();
        MunicipalityMember::factory()->create([
            'municipality_id' => $municipality->id,
            'user_id' => $user->id,
            'status' => MunicipalityMemberStatus::Active,
        ]);

        $loginUser = $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => $password,
            'device_name' => 'phone',
        ])->assertOk()->json('user');

        $me = $this->withToken(
            $this->postJson('/api/v1/auth/login', [
                'email' => $user->email,
                'password' => $password,
                'device_name' => 'phone-2',
            ])->json('token')
        )->getJson('/api/v1/me')->assertOk()->json();

        $this->assertEquals(
            array_keys($loginUser),
            array_keys($me),
        );
    }

    public function test_valid_password_succeeds_before_rate_limit_threshold(): void
    {
        $password = 'secret';
        $user = User::factory()->create(['password' => Hash::make($password)]);
        $group = NeighborhoodGroup::factory()->create();
        $this->addMemberToGroup($group, $user);

        RateLimiter::clear('mobile-login|'.mb_strtolower($user->email).'|127.0.0.1');
        RateLimiter::clear('mobile-login|ip|127.0.0.1');

        for ($i = 0; $i < 4; $i++) {
            $this->postJson('/api/v1/auth/login', [
                'email' => $user->email,
                'password' => 'wrong',
                'device_name' => 'device',
            ])->assertUnauthorized();
        }

        $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => $password,
            'device_name' => 'device',
        ])->assertOk();
    }

    public function test_rate_limit_blocks_even_correct_password_until_window_passes(): void
    {
        $password = 'secret';
        $user = User::factory()->create(['password' => Hash::make($password)]);
        $group = NeighborhoodGroup::factory()->create();
        $this->addMemberToGroup($group, $user);

        for ($i = 0; $i < 5; $i++) {
            $this->postJson('/api/v1/auth/login', [
                'email' => $user->email,
                'password' => 'wrong',
                'device_name' => 'device',
            ])->assertUnauthorized();
        }

        $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => $password,
            'device_name' => 'device',
        ])->assertStatus(429);
    }

    public function test_malformed_bearer_token_returns_unauthorized_without_server_error(): void
    {
        $this->withToken('not-a-valid-token')
            ->getJson('/api/v1/me')
            ->assertUnauthorized();
    }

    public function test_logout_with_foreign_users_token_only_affects_that_session(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $userA = User::factory()->create();
        $userB = User::factory()->create();
        $this->addMemberToGroup($group, $userA);
        $this->addMemberToGroup($group, $userB);

        $tokenA = $userA->createToken('a')->plainTextToken;
        $tokenB = $userB->createToken('b')->plainTextToken;

        [$tokenBId] = explode('|', $tokenB, 2);

        $this->withToken($tokenB)->postJson('/api/v1/auth/logout')->assertNoContent();

        $this->assertDatabaseMissing('personal_access_tokens', ['id' => $tokenBId]);
        $this->app['auth']->forgetGuards();

        $this->withToken($tokenA)->getJson('/api/v1/me')->assertOk();
        $this->app['auth']->forgetGuards();
        $this->withToken($tokenB)->getJson('/api/v1/me')->assertUnauthorized();
    }

    public function test_mobile_login_token_has_expiration_metadata(): void
    {
        config(['red_vecinal.mobile_auth.token_expiration_days' => 30]);

        $password = 'secret';
        $user = User::factory()->create(['password' => Hash::make($password)]);
        $group = NeighborhoodGroup::factory()->create();
        $this->addMemberToGroup($group, $user);

        $this->postJson('/api/v1/auth/login', [
            'email' => $user->email,
            'password' => $password,
            'device_name' => 'phone',
        ])->assertOk();

        $token = PersonalAccessToken::query()->where('tokenable_id', $user->id)->sole();
        $this->assertNotNull($token->expires_at);
        $this->assertTrue($token->expires_at->greaterThan(now()->addDays(29)));
    }

    /**
     * @return array{0: NeighborhoodGroup, 1: User}
     */
    private function vecinoWithGroup(): array
    {
        $group = NeighborhoodGroup::factory()->create();
        $vecino = User::factory()->create();
        $this->addMemberToGroup($group, $vecino);

        return [$group, $vecino];
    }
}
