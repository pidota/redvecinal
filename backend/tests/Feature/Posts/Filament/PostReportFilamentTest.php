<?php

namespace Tests\Feature\Posts\Filament;

use App\Domains\Municipality\Enums\MunicipalityMemberStatus;
use App\Domains\Municipality\Models\MunicipalityMember;
use App\Domains\Posts\Enums\PostReportStatus;
use App\Domains\Posts\Models\PostReport;
use App\Filament\Resources\PostReports\Pages\ListPostReports;
use App\Filament\Resources\PostReports\PostReportResource;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Spatie\Permission\Models\Role;
use Tests\Concerns\CreatesPostFixtures;
use Tests\Concerns\InteractsWithFilamentPanel;
use Tests\TestCase;

class PostReportFilamentTest extends TestCase
{
    use CreatesPostFixtures, InteractsWithFilamentPanel, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
        Role::findOrCreate('administrador-municipal', 'web');
    }

    public function test_municipal_admin_sees_only_own_municipality_reports(): void
    {
        [$groupA, $authorA, , $postA] = $this->publishedCommunityPost();
        [$groupB, $authorB, , $postB] = $this->publishedCommunityPost();

        $reportA = $this->createReport($postA, $authorA);
        $reportB = $this->createReport($postB, $authorB);

        $adminA = $this->municipalAdministratorFor($groupA->municipality);
        $this->authenticateForFilament($adminA);

        $visibleIds = PostReportResource::getEloquentQuery()->pluck('id')->all();
        $this->assertContains($reportA->id, $visibleIds);
        $this->assertNotContains($reportB->id, $visibleIds);

        Livewire::test(ListPostReports::class)
            ->assertCanSeeTableRecords([$reportA])
            ->assertCanNotSeeTableRecords([$reportB]);
    }

    public function test_revoked_municipal_membership_blocks_post_reports_on_next_livewire_request(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $this->createReport($post, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        Livewire::test(ListPostReports::class)->assertSuccessful();

        MunicipalityMember::query()
            ->where('user_id', $admin->id)
            ->firstOrFail()
            ->update(['status' => MunicipalityMemberStatus::Inactive]);

        $this->authenticateForFilament($admin->fresh());
        $this->assertFalse(PostReportResource::canViewAny());

        Livewire::test(ListPostReports::class)->assertForbidden();
    }

    private function createReport($post, $reporter): PostReport
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
