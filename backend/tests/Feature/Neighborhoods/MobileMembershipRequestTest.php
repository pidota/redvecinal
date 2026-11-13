<?php

namespace Tests\Feature\Neighborhoods;

use App\Domains\Municipality\Enums\MunicipalityMemberRole;
use App\Domains\Municipality\Enums\MunicipalityMemberStatus;
use App\Domains\Municipality\Models\Municipality;
use App\Domains\Municipality\Models\MunicipalityMember;
use App\Domains\Neighborhoods\Enums\MembershipRequestStatus;
use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Enums\NeighborhoodGroupStatus;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\GroupMembershipEvent;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Models\NeighborhoodMembershipRequest;
use App\Domains\Neighborhoods\Services\AddGroupMemberService;
use App\Domains\Neighborhoods\Services\AssignPresidentService;
use App\Domains\Neighborhoods\Services\RejectGroupMemberService;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class MobileMembershipRequestTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seedPostsBasics();
    }

    public function test_valid_membership_request(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);

        Sanctum::actingAs($vecino);

        $this->postJson("/api/v1/groups/{$target->id}/membership-requests", [
            'request_note' => 'Quiero participar',
        ])->assertCreated()
            ->assertJsonPath('data.status', 'pending')
            ->assertJsonPath('data.neighborhood_group_id', $target->id)
            ->assertJsonMissing(['contact_email', 'contact_phone']);
    }

    public function test_duplicate_pending_request_returns_409(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);

        Sanctum::actingAs($vecino);
        $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->assertCreated();
        $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->assertStatus(409);
    }

    public function test_active_member_cannot_request(): void
    {
        [$group, $vecino] = $this->vecinoWithGroup();
        Sanctum::actingAs($vecino);

        $this->postJson("/api/v1/groups/{$group->id}/membership-requests")->assertStatus(409);
    }

    public function test_filament_pending_blocks_api_request(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);
        $applicant = User::factory()->create();
        $this->addMemberToGroup($anchorGroup, $applicant);
        $admin = User::factory()->create();
        app(AddGroupMemberService::class)->execute($target, $applicant, $admin);

        Sanctum::actingAs($applicant);

        $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->assertStatus(409);
    }

    public function test_api_pending_blocks_filament_add(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);
        $applicant = User::factory()->create();

        NeighborhoodMembershipRequest::factory()
            ->forGroupAndUser($target, $applicant)
            ->create();

        $admin = User::factory()->create();
        $this->expectExceptionMessage('solicitud de incorporación pendiente');
        app(AddGroupMemberService::class)->execute($target, $applicant, $admin);
    }

    public function test_suspended_group_rejects_request(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->suspended()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);

        Sanctum::actingAs($vecino);

        $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->assertStatus(403);
    }

    public function test_reject_starts_cooldown(): void
    {
        Carbon::setTestNow('2026-01-01 12:00:00');

        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);
        $president = $this->makePresidentFor($target);

        Sanctum::actingAs($vecino);
        $create = $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->assertCreated();
        $requestId = $create->json('data.id');

        Sanctum::actingAs($president);
        $this->postJson("/api/v1/membership-requests/{$requestId}/reject")->assertOk();

        Sanctum::actingAs($vecino);
        $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->assertStatus(422);

        Carbon::setTestNow('2026-01-09 12:00:00');
        $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->assertCreated();

        Carbon::setTestNow();
    }

    public function test_cancelled_request_does_not_start_cooldown(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);

        Sanctum::actingAs($vecino);
        $id = $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->assertCreated()->json('data.id');
        $this->deleteJson("/api/v1/me/membership-requests/{$id}")->assertNoContent();

        $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->assertCreated();
    }

    public function test_president_can_approve_request(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);
        $president = $this->makePresidentFor($target);

        Sanctum::actingAs($vecino);
        $requestId = $this->postJson("/api/v1/groups/{$target->id}/membership-requests")
            ->assertCreated()
            ->json('data.id');

        Sanctum::actingAs($president);
        $this->postJson("/api/v1/membership-requests/{$requestId}/approve")
            ->assertOk()
            ->assertJsonPath('data.status', 'approved');

        $this->assertDatabaseHas('group_members', [
            'neighborhood_group_id' => $target->id,
            'user_id' => $vecino->id,
            'status' => MembershipStatus::Active->value,
        ]);
    }

    public function test_municipal_admin_can_approve_in_scope(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);
        $admin = $this->municipalAdministratorFor($anchorGroup->municipality);

        Sanctum::actingAs($vecino);
        $requestId = $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->json('data.id');

        Sanctum::actingAs($admin);
        $this->postJson("/api/v1/membership-requests/{$requestId}/approve")->assertOk();
    }

    public function test_superadmin_can_approve(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);
        $super = User::factory()->create();
        $super->assignRole('super-admin');

        Sanctum::actingAs($vecino);
        $requestId = $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->json('data.id');

        Sanctum::actingAs($super);
        $this->postJson("/api/v1/membership-requests/{$requestId}/approve")->assertOk();
    }

    public function test_moderator_cannot_approve(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);
        $moderator = User::factory()->create();
        $this->addMemberToGroup($target, $moderator, MembershipRole::Moderator);

        Sanctum::actingAs($vecino);
        $requestId = $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->json('data.id');

        Sanctum::actingAs($moderator);
        $this->postJson("/api/v1/membership-requests/{$requestId}/approve")->assertForbidden();
    }

    public function test_foreign_president_cannot_approve(): void
    {
        $municipality = Municipality::factory()->create();
        $groupA = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id]);
        $groupB = NeighborhoodGroup::factory()->create(['municipality_id' => $municipality->id]);
        $presidentA = $this->makePresidentFor($groupA);
        $vecino = User::factory()->create();
        $this->addMemberToGroup($groupA, $vecino);

        Sanctum::actingAs($vecino);
        $requestId = $this->postJson("/api/v1/groups/{$groupB->id}/membership-requests")->json('data.id');

        Sanctum::actingAs($presidentA);
        $this->postJson("/api/v1/membership-requests/{$requestId}/approve")->assertForbidden();
    }

    public function test_municipal_isolation_on_review(): void
    {
        $municipalityA = Municipality::factory()->create();
        $municipalityB = Municipality::factory()->create();
        $groupB = NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityB->id]);

        $anchor = NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityA->id]);
        $vecino = User::factory()->create();
        $this->addMemberToGroup($anchor, $vecino);

        $adminA = $this->municipalAdministratorFor($municipalityA);

        Sanctum::actingAs($vecino);
        $this->postJson("/api/v1/groups/{$groupB->id}/membership-requests")->assertForbidden();

        $otherInB = NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityB->id]);
        $vecinoB = User::factory()->create();
        $this->addMemberToGroup($otherInB, $vecinoB);
        Sanctum::actingAs($vecinoB);
        $requestId = $this->postJson("/api/v1/groups/{$groupB->id}/membership-requests")
            ->assertCreated()
            ->json('data.id');

        Sanctum::actingAs($adminA);
        $this->postJson("/api/v1/membership-requests/{$requestId}/approve")->assertForbidden();
    }

    public function test_idor_on_cancel(): void
    {
        [$anchorGroup, $owner] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);
        $intruder = User::factory()->create();
        $this->addMemberToGroup($anchorGroup, $intruder);

        Sanctum::actingAs($owner);
        $requestId = $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->json('data.id');

        Sanctum::actingAs($intruder);
        $this->deleteJson("/api/v1/me/membership-requests/{$requestId}")->assertForbidden();
    }

    public function test_double_approve_is_idempotent_conflict(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);
        $president = $this->makePresidentFor($target);

        Sanctum::actingAs($vecino);
        $requestId = $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->json('data.id');

        Sanctum::actingAs($president);
        $this->postJson("/api/v1/membership-requests/{$requestId}/approve")->assertOk();
        $this->postJson("/api/v1/membership-requests/{$requestId}/approve")->assertStatus(409);
    }

    public function test_reactivate_left_membership_on_approve(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);
        $president = $this->makePresidentFor($target);

        GroupMember::factory()->create([
            'neighborhood_group_id' => $target->id,
            'municipality_id' => $target->municipality_id,
            'user_id' => $vecino->id,
            'status' => MembershipStatus::Left,
        ]);

        Sanctum::actingAs($vecino);
        $requestId = $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->assertCreated()->json('data.id');

        Sanctum::actingAs($president);
        $this->postJson("/api/v1/membership-requests/{$requestId}/approve")->assertOk();

        $this->assertDatabaseHas('group_members', [
            'neighborhood_group_id' => $target->id,
            'user_id' => $vecino->id,
            'status' => MembershipStatus::Active->value,
        ]);
    }

    public function test_approval_records_membership_audit_event(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);
        $president = $this->makePresidentFor($target);

        Sanctum::actingAs($vecino);
        $requestId = $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->json('data.id');

        Sanctum::actingAs($president);
        $this->postJson("/api/v1/membership-requests/{$requestId}/approve")->assertOk();

        $member = GroupMember::query()
            ->where('neighborhood_group_id', $target->id)
            ->where('user_id', $vecino->id)
            ->first();

        $this->assertNotNull($member);
        $this->assertTrue(
            GroupMembershipEvent::query()
                ->where('group_member_id', $member->id)
                ->whereIn('event', ['approved', 'reactivated'])
                ->exists()
        );
    }

    public function test_membership_context_without_private_show(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
            'contact_email' => 'privado@example.com',
        ]);

        Sanctum::actingAs($vecino);

        $this->getJson("/api/v1/groups/{$target->id}")->assertForbidden();
        $this->getJson("/api/v1/groups/{$target->id}/membership-context")
            ->assertOk()
            ->assertJsonPath('data.id', $target->id)
            ->assertJsonMissing(['contact_email', 'contact_phone']);
    }

    public function test_president_can_approve_group_member_via_policy(): void
    {
        $group = NeighborhoodGroup::factory()->create();
        $president = User::factory()->create();
        $admin = User::factory()->create();
        $pendingUser = User::factory()->create();

        $add = app(AddGroupMemberService::class);
        $add->execute($group, $president, $admin, MembershipStatus::Active);
        app(AssignPresidentService::class)->execute($group, $president, $admin);

        $pendingMember = $add->execute($group, $pendingUser, $admin);

        $this->assertTrue($president->can('approve', $pendingMember));
    }

    public function test_my_requests_list_paginated(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();

        Sanctum::actingAs($vecino);

        $this->getJson('/api/v1/me/membership-requests')
            ->assertOk()
            ->assertJsonStructure(['data', 'links', 'meta']);
    }

    public function test_my_requests_filter_by_neighborhood_group_id(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $targetA = NeighborhoodGroup::factory()->create(['municipality_id' => $anchorGroup->municipality_id]);
        $targetB = NeighborhoodGroup::factory()->create(['municipality_id' => $anchorGroup->municipality_id]);

        Sanctum::actingAs($vecino);
        $idA = $this->postJson("/api/v1/groups/{$targetA->id}/membership-requests")->assertCreated()->json('data.id');
        $this->postJson("/api/v1/groups/{$targetB->id}/membership-requests")->assertCreated();

        $this->getJson("/api/v1/me/membership-requests?neighborhood_group_id={$targetA->id}")
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $idA)
            ->assertJsonPath('data.0.neighborhood_group_id', $targetA->id);
    }

    public function test_my_requests_filter_returns_empty_when_no_requests_for_group(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $emptyGroup = NeighborhoodGroup::factory()->create(['municipality_id' => $anchorGroup->municipality_id]);

        Sanctum::actingAs($vecino);

        $this->getJson("/api/v1/me/membership-requests?neighborhood_group_id={$emptyGroup->id}")
            ->assertOk()
            ->assertJsonPath('data', [])
            ->assertJsonPath('meta.total', 0);
    }

    public function test_my_requests_filter_allows_nonexistent_group_id_with_empty_collection(): void
    {
        [, $vecino] = $this->vecinoWithGroup();

        Sanctum::actingAs($vecino);

        $this->getJson('/api/v1/me/membership-requests?neighborhood_group_id=999999')
            ->assertOk()
            ->assertJsonPath('data', []);
    }

    public function test_my_requests_filter_never_exposes_other_users_requests(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create(['municipality_id' => $anchorGroup->municipality_id]);
        $other = User::factory()->create();
        $this->addMemberToGroup($anchorGroup, $other);

        Sanctum::actingAs($other);
        $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->assertCreated();

        Sanctum::actingAs($vecino);
        $this->getJson("/api/v1/me/membership-requests?neighborhood_group_id={$target->id}")
            ->assertOk()
            ->assertJsonPath('data', []);
    }

    public function test_my_requests_filter_respects_municipalities(): void
    {
        $municipalityA = Municipality::factory()->create();
        $municipalityB = Municipality::factory()->create();
        $groupA = NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityA->id]);
        $groupB = NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityB->id]);
        $anchorA = NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityA->id]);
        $anchorB = NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityB->id]);
        $vecino = User::factory()->create();
        $this->addMemberToGroup($anchorA, $vecino);
        $this->addMemberToGroup($anchorB, $vecino);

        $requestB = NeighborhoodMembershipRequest::factory()->create([
            'neighborhood_group_id' => $groupB->id,
            'user_id' => $vecino->id,
            'municipality_id' => $municipalityB->id,
            'status' => MembershipRequestStatus::Pending,
        ]);
        NeighborhoodMembershipRequest::factory()->create([
            'neighborhood_group_id' => $groupA->id,
            'user_id' => $vecino->id,
            'municipality_id' => $municipalityA->id,
            'status' => MembershipRequestStatus::Pending,
        ]);

        Sanctum::actingAs($vecino);

        $this->getJson("/api/v1/me/membership-requests?neighborhood_group_id={$groupB->id}")
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $requestB->id);

        $this->getJson("/api/v1/me/membership-requests?neighborhood_group_id={$groupA->id}")
            ->assertOk()
            ->assertJsonCount(1, 'data');
    }

    public function test_my_requests_filter_rejects_malformed_group_id(): void
    {
        [, $vecino] = $this->vecinoWithGroup();

        Sanctum::actingAs($vecino);

        $this->getJson('/api/v1/me/membership-requests?neighborhood_group_id=abc')
            ->assertStatus(422)
            ->assertJsonValidationErrors(['neighborhood_group_id']);
    }

    public function test_my_requests_filter_keeps_order_and_pagination(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create(['municipality_id' => $anchorGroup->municipality_id]);

        NeighborhoodMembershipRequest::factory()->create([
            'neighborhood_group_id' => $target->id,
            'user_id' => $vecino->id,
            'municipality_id' => $target->municipality_id,
            'status' => MembershipRequestStatus::Rejected,
            'rejected_at' => now()->subDays(3),
            'created_at' => now()->subDays(3),
        ]);
        $newer = NeighborhoodMembershipRequest::factory()->create([
            'neighborhood_group_id' => $target->id,
            'user_id' => $vecino->id,
            'municipality_id' => $target->municipality_id,
            'status' => MembershipRequestStatus::Pending,
            'created_at' => now()->subHour(),
        ]);

        Sanctum::actingAs($vecino);

        $this->getJson("/api/v1/me/membership-requests?neighborhood_group_id={$target->id}")
            ->assertOk()
            ->assertJsonPath('data.0.id', $newer->id)
            ->assertJsonStructure(['data', 'links', 'meta']);
    }

    public function test_unauthenticated_requests_return_401(): void
    {
        $group = NeighborhoodGroup::factory()->create();

        $this->postJson("/api/v1/groups/{$group->id}/membership-requests")->assertUnauthorized();
        $this->getJson('/api/v1/me/membership-requests')->assertUnauthorized();
    }

    public function test_suspended_president_cannot_approve(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);
        $president = $this->makePresidentFor($target);

        GroupMember::query()
            ->where('neighborhood_group_id', $target->id)
            ->where('user_id', $president->id)
            ->update(['status' => MembershipStatus::Suspended]);

        Sanctum::actingAs($vecino);
        $requestId = $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->json('data.id');

        Sanctum::actingAs($president);
        $this->postJson("/api/v1/membership-requests/{$requestId}/approve")->assertForbidden();
    }

    public function test_president_lists_pending_for_group(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);
        $president = $this->makePresidentFor($target);

        Sanctum::actingAs($vecino);
        $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->assertCreated();

        Sanctum::actingAs($president);
        $this->getJson("/api/v1/groups/{$target->id}/membership-requests")
            ->assertOk()
            ->assertJsonPath('data.0.status', 'pending');
    }

    public function test_sequential_duplicate_posts_conflict(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);

        Sanctum::actingAs($vecino);
        $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->assertCreated();
        $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->assertStatus(409);
    }

    public function test_filament_reject_triggers_api_cooldown(): void
    {
        Carbon::setTestNow('2026-02-01 10:00:00');

        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);
        $admin = User::factory()->create();
        $pendingViaPanel = app(AddGroupMemberService::class)->execute($target, $vecino, $admin);
        app(RejectGroupMemberService::class)->execute($pendingViaPanel, $admin);

        Sanctum::actingAs($vecino);
        $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->assertStatus(422);

        Carbon::setTestNow('2026-02-09 10:00:00');
        $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->assertCreated();

        Carbon::setTestNow();
    }

    public function test_member_cannot_list_group_requests(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);

        Sanctum::actingAs($vecino);
        $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->assertCreated();
        $this->getJson("/api/v1/groups/{$target->id}/membership-requests")->assertForbidden();
    }

    public function test_store_rate_limit_returns_429(): void
    {
        config(['red_vecinal.membership_requests.store_per_user_per_hour' => 2]);

        [$anchorGroup, $vecino] = $this->vecinoWithGroup();

        Sanctum::actingAs($vecino);

        for ($i = 0; $i < 2; $i++) {
            $group = NeighborhoodGroup::factory()->create([
                'municipality_id' => $anchorGroup->municipality_id,
            ]);
            $this->postJson("/api/v1/groups/{$group->id}/membership-requests")->assertCreated();
        }

        $extra = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);
        $this->postJson("/api/v1/groups/{$extra->id}/membership-requests")->assertStatus(429);
    }

    public function test_cannot_approve_cancelled_request(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);
        $president = $this->makePresidentFor($target);

        Sanctum::actingAs($vecino);
        $id = $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->json('data.id');
        $this->deleteJson("/api/v1/me/membership-requests/{$id}")->assertNoContent();

        Sanctum::actingAs($president);
        $this->postJson("/api/v1/membership-requests/{$id}/approve")
            ->assertStatus(409)
            ->assertJsonStructure(['message']);
    }

    public function test_membership_request_resource_hides_sensitive_fields(): void
    {
        [$anchorGroup, $vecino] = $this->vecinoWithGroup();
        $target = NeighborhoodGroup::factory()->create([
            'municipality_id' => $anchorGroup->municipality_id,
        ]);
        $president = $this->makePresidentFor($target);

        Sanctum::actingAs($vecino);
        $id = $this->postJson("/api/v1/groups/{$target->id}/membership-requests")->json('data.id');

        Sanctum::actingAs($president);
        $this->getJson("/api/v1/groups/{$target->id}/membership-requests")
            ->assertOk()
            ->assertJsonMissing(['email', 'rut', 'phone', 'contact_phone', 'contact_email', 'token']);
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

    private function makePresidentFor(NeighborhoodGroup $group): User
    {
        $president = User::factory()->create();
        $admin = User::factory()->create();
        $add = app(AddGroupMemberService::class);
        $add->execute($group, $president, $admin, MembershipStatus::Active);
        app(AssignPresidentService::class)->execute($group, $president, $admin);

        return $president;
    }
}
