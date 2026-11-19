<?php

namespace Tests\Feature\Posts;

use App\Domains\Municipality\Enums\MunicipalityMemberRole;
use App\Domains\Municipality\Enums\MunicipalityMemberStatus;
use App\Domains\Municipality\Models\Municipality;
use App\Domains\Municipality\Models\MunicipalityMember;
use App\Domains\Posts\Enums\PostReportStatus;
use App\Domains\Posts\Models\PostReport;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Role;
use Spatie\Permission\PermissionRegistrar;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class PostReportPolicyTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_super_admin_with_permission_can_view_any_and_resolve_foreign_report(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $super = $this->superAdmin();

        $this->assertTrue($super->can('viewAny', PostReport::class));
        $this->assertTrue($super->can('view', $report));
        $this->assertTrue($super->can('resolve', $report));
        $this->assertTrue($super->can('view', PostReport::query()->findOrFail($report->id)));
    }

    public function test_super_admin_without_view_permission_is_denied(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $super = $this->superAdmin();

        Role::findByName('super-admin', 'web')->revokePermissionTo('posts.reports.view');
        app(PermissionRegistrar::class)->forgetCachedPermissions();
        $super = $super->fresh();

        $this->assertFalse($super->can('posts.reports.view'));
        $this->assertFalse($super->can('viewAny', PostReport::class));
        $this->assertFalse($super->can('view', $report));
        $this->assertTrue($super->can('resolve', $report));
    }

    public function test_super_admin_without_resolve_permission_cannot_resolve(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $super = $this->superAdmin();

        Role::findByName('super-admin', 'web')->revokePermissionTo('posts.reports.resolve');
        app(PermissionRegistrar::class)->forgetCachedPermissions();
        $super = $super->fresh();

        $this->assertTrue($super->can('view', $report));
        $this->assertFalse($super->can('resolve', $report));
    }

    public function test_municipal_admin_of_report_municipality_can_view_and_resolve(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);

        $this->assertTrue($admin->can('viewAny', PostReport::class));
        $this->assertTrue($admin->can('view', $report));
        $this->assertTrue($admin->can('resolve', $report));
        $this->assertTrue($admin->can('view', PostReport::query()->findOrFail($report->id)));
    }

    public function test_foreign_municipal_admin_cannot_view_or_resolve_by_report_id(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $foreign = $this->municipalAdministratorFor(Municipality::factory()->create());

        $this->assertTrue($foreign->can('viewAny', PostReport::class));
        $this->assertFalse($foreign->can('view', $report));
        $this->assertFalse($foreign->can('resolve', $report));
        $this->assertFalse($foreign->can('view', PostReport::query()->findOrFail($report->id)));
        $this->assertFalse($foreign->can('resolve', PostReport::query()->findOrFail($report->id)));
    }

    public function test_active_non_admin_municipal_member_is_denied_even_with_permissions(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $funcionario = User::factory()->create();
        MunicipalityMember::factory()->create([
            'municipality_id' => $group->municipality_id,
            'user_id' => $funcionario->id,
            'role' => MunicipalityMemberRole::Funcionario,
            'status' => MunicipalityMemberStatus::Active,
        ]);
        $funcionario->givePermissionTo(['posts.reports.view', 'posts.reports.resolve']);

        $this->assertFalse($funcionario->can('viewAny', PostReport::class));
        $this->assertFalse($funcionario->can('view', $report));
        $this->assertFalse($funcionario->can('resolve', $report));
    }

    public function test_user_without_permissions_is_denied(): void
    {
        [$group, $author, $moderator, $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $vecino = User::factory()->create();

        $this->assertFalse($vecino->can('viewAny', PostReport::class));
        $this->assertFalse($vecino->can('view', $report));
        $this->assertFalse($vecino->can('resolve', $report));
        $this->assertFalse($moderator->can('viewAny', PostReport::class));
        $this->assertFalse($moderator->can('view', $report));
        $this->assertFalse($author->can('resolve', $report));
    }

    public function test_admin_of_a_who_is_non_admin_member_of_b_cannot_access_b_report(): void
    {
        [$groupA] = $this->publishedCommunityPost();
        [$groupB, $authorB, , $postB] = $this->publishedCommunityPost();
        $reportB = $this->createOpenReport($postB, $authorB);
        $adminA = $this->municipalAdministratorFor($groupA->municipality);
        MunicipalityMember::factory()->create([
            'municipality_id' => $groupB->municipality_id,
            'user_id' => $adminA->id,
            'role' => MunicipalityMemberRole::Funcionario,
            'status' => MunicipalityMemberStatus::Active,
        ]);
        $adminA = $adminA->fresh();

        $this->assertTrue($adminA->can('viewAny', PostReport::class));
        $this->assertFalse($adminA->can('view', $reportB));
        $this->assertFalse($adminA->can('resolve', $reportB));
        $this->assertFalse($adminA->can('view', PostReport::query()->findOrFail($reportB->id)));
        $this->assertFalse($adminA->can('resolve', PostReport::query()->findOrFail($reportB->id)));
    }

    public function test_revoked_municipal_membership_loses_view_any_and_record_access(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $report = $this->createOpenReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);

        $this->assertTrue($admin->can('viewAny', PostReport::class));

        MunicipalityMember::query()
            ->where('user_id', $admin->id)
            ->firstOrFail()
            ->update(['status' => MunicipalityMemberStatus::Inactive]);

        $admin = $admin->fresh();

        $this->assertFalse($admin->can('viewAny', PostReport::class));
        $this->assertFalse($admin->can('view', $report));
        $this->assertFalse($admin->can('resolve', $report));
    }

    private function superAdmin(): User
    {
        $user = User::factory()->create();
        $user->assignRole('super-admin');

        return $user->fresh();
    }

    private function createOpenReport($post, User $reporter): PostReport
    {
        return PostReport::query()->create([
            'post_id' => $post->id,
            'municipality_id' => $post->municipality_id,
            'reporter_id' => $reporter->id,
            'reason_code' => 'inappropriate',
            'status' => PostReportStatus::Open,
        ]);
    }
}
