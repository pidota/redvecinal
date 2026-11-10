<?php

namespace Tests\Feature\Posts;

use App\Domains\Municipality\Models\Municipality;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class PostMunicipalAttachmentIsolationTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
        Storage::fake('posts_private');
    }

    public function test_user_from_other_municipality_cannot_download_attachment(): void
    {
        $municipalityA = Municipality::factory()->create(['slug' => 'a-comuna']);
        $municipalityB = Municipality::factory()->create(['slug' => 'b-comuna']);
        $groupA = \App\Domains\Neighborhoods\Models\NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityA->id]);
        $groupB = \App\Domains\Neighborhoods\Models\NeighborhoodGroup::factory()->create(['municipality_id' => $municipalityB->id]);
        $authorA = \App\Models\User::factory()->create();
        $modA = \App\Models\User::factory()->create();
        $vecinoB = \App\Models\User::factory()->create();
        $this->addMemberToGroup($groupA, $authorA);
        $this->addMemberToGroup($groupA, $modA, \App\Domains\Neighborhoods\Enums\MembershipRole::Moderator);
        $this->addMemberToGroup($groupB, $vecinoB);

        $post = app(\App\Domains\Posts\Services\CreateCommunityPostService::class)->execute(
            $groupA,
            $authorA,
            $this->postCategory->id,
            'Solo A',
            'Contenido',
        );
        $revision = $post->revisions()->first();
        $file = UploadedFile::fake()->createWithContent('doc.pdf', "%PDF-1.4\n%%EOF");
        $attachment = app(\App\Domains\Posts\Services\AttachPostFileService::class)->execute($revision, $authorA, $file);
        app(\App\Domains\Posts\Services\SubmitPostService::class)->execute($post, $authorA);
        app(\App\Domains\Posts\Services\ApprovePostService::class)->execute($post->fresh(), $modA);

        Sanctum::actingAs($vecinoB);
        $this->getJson("/api/v1/posts/{$post->id}/attachments/{$attachment->id}")->assertNotFound();
    }
}
