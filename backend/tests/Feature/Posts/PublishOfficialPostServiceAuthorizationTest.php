<?php

namespace Tests\Feature\Posts;

use App\Domains\Municipality\Enums\MunicipalityMemberStatus;
use App\Domains\Municipality\Models\Municipality;
use App\Domains\Municipality\Models\MunicipalityMember;
use App\Domains\Posts\Services\PublishOfficialPostService;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Spatie\Permission\Models\Role;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class PublishOfficialPostServiceAuthorizationTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
        Role::findOrCreate('super-admin', 'web');
        Role::findOrCreate('administrador-municipal', 'web');
    }

    public function test_authorized_municipal_admin_can_publish_official_post(): void
    {
        [$group] = $this->activeGroupTriple();
        $admin = $this->municipalAdministratorFor($group->municipality);

        $post = app(PublishOfficialPostService::class)->execute(
            $group->municipality,
            $admin,
            $this->postCategory->id,
            'Oficial',
            'Cuerpo',
        );

        $this->assertTrue($post->isMunicipal());
        $this->assertSame($group->municipality_id, $post->municipality_id);
    }

    public function test_foreign_municipal_admin_cannot_publish_in_other_municipality(): void
    {
        [$groupA] = $this->activeGroupTriple();
        $municipalityB = Municipality::factory()->create();
        $adminB = $this->municipalAdministratorFor($municipalityB);

        $this->expectException(\Illuminate\Auth\Access\AuthorizationException::class);
        app(PublishOfficialPostService::class)->execute(
            $groupA->municipality,
            $adminB,
            $this->postCategory->id,
            'Indebido',
            'Texto',
        );
    }

    public function test_user_without_permissions_cannot_publish_official_post(): void
    {
        [$group] = $this->activeGroupTriple();
        $vecino = User::factory()->create();

        $this->expectException(\Illuminate\Auth\Access\AuthorizationException::class);
        app(PublishOfficialPostService::class)->execute(
            $group->municipality,
            $vecino,
            $this->postCategory->id,
            'Indebido',
            'Texto',
        );
    }

    public function test_super_admin_can_publish_in_any_municipality(): void
    {
        [$group] = $this->activeGroupTriple();
        $super = User::factory()->create();
        $super->assignRole('super-admin');

        $post = app(PublishOfficialPostService::class)->execute(
            $group->municipality,
            $super,
            $this->postCategory->id,
            'Super',
            'Cuerpo',
        );

        $this->assertTrue($post->isMunicipal());
    }

    public function test_revoked_municipal_membership_cannot_publish_official_post(): void
    {
        [$group] = $this->activeGroupTriple();
        $admin = $this->municipalAdministratorFor($group->municipality);

        $member = MunicipalityMember::query()
            ->where('user_id', $admin->id)
            ->firstOrFail();
        $member->update(['status' => MunicipalityMemberStatus::Inactive]);

        $this->expectException(\Illuminate\Auth\Access\AuthorizationException::class);
        app(PublishOfficialPostService::class)->execute(
            $group->municipality,
            $admin->fresh(),
            $this->postCategory->id,
            'Tras revocación',
            'Texto',
        );
    }
}
