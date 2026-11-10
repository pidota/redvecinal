<?php

namespace Tests\Concerns;

use App\Domains\Municipality\Enums\MunicipalityMemberRole;
use App\Domains\Municipality\Enums\MunicipalityMemberStatus;
use App\Domains\Municipality\Models\Municipality;
use App\Domains\Municipality\Models\MunicipalityMember;
use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostCategory;
use App\Domains\Posts\Services\ApprovePostService;
use App\Domains\Posts\Services\CreateCommunityPostService;
use App\Domains\Posts\Services\SubmitPostService;
use App\Models\User;
use Database\Seeders\PostCategorySeeder;
use Database\Seeders\RolesAndPermissionsSeeder;

trait CreatesPostFixtures
{
    protected PostCategory $postCategory;

    protected function seedPostsBasics(): void
    {
        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seed(PostCategorySeeder::class);
        $this->postCategory = PostCategory::query()->where('slug', 'aviso-comunitario')->firstOrFail();
    }

    protected function publishedCommunityPost(): array
    {
        [$group, $author, $moderator] = $this->activeGroupTriple();

        $post = app(CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->postCategory->id,
            'Título publicado',
            'Cuerpo publicado',
        );
        app(SubmitPostService::class)->execute($post, $author);
        app(ApprovePostService::class)->execute($post->fresh(), $moderator);

        return [$group, $author, $moderator, $post->fresh(['currentPublishedRevision', 'neighborhoodGroup'])];
    }

    protected function activeGroupTriple(): array
    {
        $group = NeighborhoodGroup::factory()->create();
        $author = User::factory()->create();
        $moderator = User::factory()->create();

        GroupMember::factory()->create([
            'neighborhood_group_id' => $group->id,
            'municipality_id' => $group->municipality_id,
            'user_id' => $author->id,
            'membership_role' => MembershipRole::Member,
            'status' => MembershipStatus::Active,
        ]);
        GroupMember::factory()->create([
            'neighborhood_group_id' => $group->id,
            'municipality_id' => $group->municipality_id,
            'user_id' => $moderator->id,
            'membership_role' => MembershipRole::Moderator,
            'status' => MembershipStatus::Active,
        ]);

        return [$group, $author, $moderator];
    }

    protected function municipalAdministratorFor(Municipality $municipality): User
    {
        $user = User::factory()->create();
        MunicipalityMember::factory()->create([
            'municipality_id' => $municipality->id,
            'user_id' => $user->id,
            'role' => MunicipalityMemberRole::Administrador,
            'status' => MunicipalityMemberStatus::Active,
        ]);
        $user->assignRole('administrador-municipal');

        return $user->fresh();
    }

    protected function addMemberToGroup(NeighborhoodGroup $group, User $user, MembershipRole $role = MembershipRole::Member): void
    {
        GroupMember::factory()->create([
            'neighborhood_group_id' => $group->id,
            'municipality_id' => $group->municipality_id,
            'user_id' => $user->id,
            'membership_role' => $role,
            'status' => MembershipStatus::Active,
        ]);
    }
}
