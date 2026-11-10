<?php

namespace Tests\Feature\Posts\Filament;

use App\Domains\Posts\Services\ApprovePostService;
use App\Domains\Posts\Services\CreateCommunityPostService;
use App\Domains\Posts\Services\RejectPostService;
use App\Domains\Posts\Services\SubmitPostService;
use App\Domains\Posts\Exceptions\PostDomainException;
use App\Filament\Pages\ModerationQueue;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Livewire\Livewire;
use Spatie\Permission\Models\Role;
use Tests\Concerns\CreatesPostFixtures;
use Tests\Concerns\InteractsWithFilamentPanel;
use Tests\TestCase;

class ModerationQueueFilamentTest extends TestCase
{
    use CreatesPostFixtures, InteractsWithFilamentPanel, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
        Role::findOrCreate('super-admin', 'web');
        Role::findOrCreate('administrador-municipal', 'web');
    }

    public function test_queue_lists_pending_posts_for_municipality_only(): void
    {
        [$groupA, $authorA, $modA] = $this->activeGroupTriple();
        [$groupB, $authorB, $modB] = $this->activeGroupTriple();
        $pendingA = $this->createPendingPost($groupA, $authorA);
        $pendingB = $this->createPendingPost($groupB, $authorB);
        $adminA = $this->municipalAdministratorFor($groupA->municipality);
        $this->authenticateForFilament($adminA);

        Livewire::test(ModerationQueue::class)
            ->assertCanSeeTableRecords([$pendingA])
            ->assertCanNotSeeTableRecords([$pendingB]);
    }

    public function test_super_admin_sees_all_pending_posts_in_queue(): void
    {
        [$groupA, $authorA] = $this->activeGroupTriple();
        [$groupB, $authorB] = $this->activeGroupTriple();
        $pendingA = $this->createPendingPost($groupA, $authorA);
        $pendingB = $this->createPendingPost($groupB, $authorB);
        $super = \App\Models\User::factory()->create();
        $super->assignRole('super-admin');
        $this->authenticateForFilament($super);

        Livewire::test(ModerationQueue::class)
            ->assertCanSeeTableRecords([$pendingA, $pendingB]);
    }

    public function test_queue_table_has_no_approve_or_reject_actions(): void
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();
        $pending = $this->createPendingPost($group, $author);
        $admin = $this->municipalAdministratorFor($group->municipality);
        $this->authenticateForFilament($admin);

        $component = Livewire::test(ModerationQueue::class);
        $table = $component->instance()->getTable();
        $this->assertSame([], $table->getRecordActions());
    }

    public function test_municipal_admin_still_cannot_approve_from_domain_layer(): void
    {
        [$group, $author, $mod] = $this->activeGroupTriple();
        $admin = $this->municipalAdministratorFor($group->municipality);
        $post = $this->createPendingPost($group, $author);

        $this->expectException(PostDomainException::class);
        $this->actingAs($admin);
        app(ApprovePostService::class)->execute($post, $admin);
    }

    private function createPendingPost($group, $author)
    {
        $post = app(CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->postCategory->id,
            'Pendiente cola',
            'Contenido',
        );
        app(SubmitPostService::class)->execute($post, $author);

        return $post->fresh();
    }
}
