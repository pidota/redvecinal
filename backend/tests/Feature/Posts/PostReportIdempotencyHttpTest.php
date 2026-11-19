<?php

namespace Tests\Feature\Posts;

use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Posts\Enums\PostReportStatus;
use App\Domains\Posts\Exceptions\PostReportIdempotencyException;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostModerationEvent;
use App\Domains\Posts\Models\PostReport;
use App\Domains\Posts\Services\CreateCommunityPostService;
use App\Domains\Posts\Services\ReportPostService;
use App\Domains\Posts\Services\SubmitPostService;
use App\Domains\Posts\Services\TransitionPostReportService;
use App\Domains\Posts\Support\PostReportIdempotency;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class PostReportIdempotencyHttpTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    private const KEY = '550e8400-e29b-41d4-a716-446655440000';

    private const KEY_B = '123e4567-e89b-42d3-a456-426614174000';

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_first_keyed_request_persists_normalized_key_and_fingerprint(): void
    {
        [$reporter, $post] = $this->memberWithPublishedPost();
        Sanctum::actingAs($reporter);

        $response = $this->report($post->id, ['reason_code' => 'spam', 'details' => 'Uno'], self::KEY);

        $response->assertCreated()->assertExactJson([
            'id' => $response->json('id'),
            'status' => PostReportStatus::Open->value,
        ]);
        $response->assertJsonMissing(['reporter_id', 'idempotency_key', 'payload_fingerprint']);

        $record = PostReport::query()->findOrFail($response->json('id'));
        $this->assertSame(self::KEY, $record->idempotency_key);
        $this->assertSame(
            PostReportIdempotency::fingerprint($post->id, 'spam', 'Uno'),
            $record->payload_fingerprint,
        );
        $this->assertSame(PostReportStatus::Open, $record->status);
    }

    public function test_exact_replay_returns_same_id_and_creation_json_without_second_row(): void
    {
        [$reporter, $post] = $this->memberWithPublishedPost();
        Sanctum::actingAs($reporter);
        $payload = ['reason_code' => 'spam', 'details' => 'Uno'];

        $first = $this->report($post->id, $payload, self::KEY);
        $second = $this->report($post->id, $payload, self::KEY);

        $first->assertCreated();
        $second->assertCreated()->assertExactJson([
            'id' => $first->json('id'),
            'status' => PostReportStatus::Open->value,
        ]);
        $this->assertSame($first->json('id'), $second->json('id'));
        $this->assertSame(1, PostReport::query()->where('reporter_id', $reporter->id)->count());
    }

    public function test_same_key_with_different_reason_code_conflicts(): void
    {
        [$reporter, $post] = $this->memberWithPublishedPost();
        Sanctum::actingAs($reporter);

        $this->report($post->id, ['reason_code' => 'spam'], self::KEY)->assertCreated();
        $conflict = $this->report($post->id, ['reason_code' => 'inappropriate'], self::KEY);

        $conflict->assertStatus(409)->assertJsonPath('message', 'La clave de idempotencia ya fue usada con otro contenido.');
        $this->assertSame(1, PostReport::query()->where('reporter_id', $reporter->id)->count());
        $this->assertSame('spam', PostReport::query()->first()->reason_code);
    }

    public function test_same_key_with_different_details_conflicts(): void
    {
        [$reporter, $post] = $this->memberWithPublishedPost();
        Sanctum::actingAs($reporter);

        $this->report($post->id, ['reason_code' => 'spam', 'details' => 'A'], self::KEY)->assertCreated();
        $this->report($post->id, ['reason_code' => 'spam', 'details' => 'B'], self::KEY)->assertStatus(409);
        $this->assertSame('A', PostReport::query()->first()->details);
    }

    public function test_http_empty_details_string_matches_omitted_details_via_existing_middleware(): void
    {
        [$reporter, $post] = $this->memberWithPublishedPost();
        Sanctum::actingAs($reporter);

        $first = $this->report($post->id, ['reason_code' => 'spam'], self::KEY)->assertCreated();
        $second = $this->report($post->id, ['reason_code' => 'spam', 'details' => ''], self::KEY)->assertCreated();

        $this->assertSame($first->json('id'), $second->json('id'));
        $this->assertNull(PostReport::query()->first()->details);
        $this->assertSame(1, PostReport::query()->count());
    }

    public function test_service_treats_null_details_and_empty_string_as_distinct_fingerprints(): void
    {
        [$reporter, $post] = $this->memberWithPublishedPost();
        $service = app(ReportPostService::class);

        $service->execute($reporter, 'spam', $post, null, null, self::KEY);
        try {
            $service->execute($reporter, 'spam', $post, null, '', self::KEY);
            $this->fail('null y string vacío deben conflictuar en el servicio.');
        } catch (PostReportIdempotencyException $exception) {
            $this->assertSame(409, $exception->httpStatus);
        }

        $this->assertSame(1, PostReport::query()->count());
        $this->assertNull(PostReport::query()->first()->details);
    }

    public function test_same_key_on_another_post_conflicts_without_creating(): void
    {
        [$group, $reporter, $postA] = $this->memberOnGroupWithPost();
        [, , , $postB] = $this->publishedCommunityPost();
        $this->addMemberToGroup($postB->neighborhoodGroup, $reporter);
        Sanctum::actingAs($reporter);

        $created = $this->report($postA->id, ['reason_code' => 'spam'], self::KEY);
        $created->assertCreated();
        $this->report($postB->id, ['reason_code' => 'spam'], self::KEY)->assertStatus(409);

        $this->assertSame(1, PostReport::query()->count());
        $this->assertSame($postA->id, PostReport::query()->first()->post_id);
        $this->assertSame($group->id, $postA->neighborhood_group_id);
    }

    public function test_same_key_is_isolated_per_user(): void
    {
        [$group, $firstReporter, $post] = $this->memberOnGroupWithPost();
        $secondReporter = User::factory()->create();
        $this->addMemberToGroup($group, $secondReporter);

        Sanctum::actingAs($firstReporter);
        $a = $this->report($post->id, ['reason_code' => 'spam'], self::KEY)->assertCreated();

        Sanctum::actingAs($secondReporter);
        $b = $this->report($post->id, ['reason_code' => 'spam'], self::KEY)->assertCreated();

        $this->assertNotSame($a->json('id'), $b->json('id'));
        $this->assertSame(2, PostReport::query()->where('idempotency_key', self::KEY)->count());
        $this->assertSame($firstReporter->id, PostReport::query()->find($a->json('id'))->reporter_id);
        $this->assertSame($secondReporter->id, PostReport::query()->find($b->json('id'))->reporter_id);
    }

    public function test_two_distinct_keys_create_two_reports(): void
    {
        [$reporter, $post] = $this->memberWithPublishedPost();
        Sanctum::actingAs($reporter);

        $a = $this->report($post->id, ['reason_code' => 'spam'], self::KEY)->assertCreated();
        $b = $this->report($post->id, ['reason_code' => 'spam'], self::KEY_B)->assertCreated();

        $this->assertNotSame($a->json('id'), $b->json('id'));
        $this->assertSame(2, PostReport::query()->where('reporter_id', $reporter->id)->count());
    }

    public function test_legacy_requests_without_header_still_insert_each_time(): void
    {
        [$reporter, $post] = $this->memberWithPublishedPost();
        Sanctum::actingAs($reporter);

        $a = $this->postJson("/api/v1/posts/{$post->id}/reports", ['reason_code' => 'spam'])->assertCreated();
        $b = $this->postJson("/api/v1/posts/{$post->id}/reports", ['reason_code' => 'spam'])->assertCreated();

        $this->assertNotSame($a->json('id'), $b->json('id'));
        $this->assertSame(2, PostReport::query()->where('reporter_id', $reporter->id)->whereNull('idempotency_key')->count());
    }

    public function test_empty_header_is_unprocessable_and_does_not_create(): void
    {
        [$reporter, $post] = $this->memberWithPublishedPost();
        Sanctum::actingAs($reporter);

        $this->withHeader(PostReportIdempotency::HEADER, '')
            ->postJson("/api/v1/posts/{$post->id}/reports", ['reason_code' => 'spam'])
            ->assertUnprocessable();

        $this->assertSame(0, PostReport::query()->count());
    }

    public function test_invalid_and_non_v4_uuids_are_unprocessable(): void
    {
        [$reporter, $post] = $this->memberWithPublishedPost();
        Sanctum::actingAs($reporter);

        $this->report($post->id, ['reason_code' => 'spam'], 'no-es-uuid')->assertUnprocessable();
        $this->report($post->id, ['reason_code' => 'spam'], '550e8400-e29b-11d4-a716-446655440000')->assertUnprocessable();
        $this->report($post->id, ['reason_code' => 'spam'], ' 550e8400-e29b-41d4-a716-446655440000')->assertUnprocessable();

        $this->assertSame(0, PostReport::query()->count());
    }

    public function test_uppercase_key_is_stored_lowercase_and_replays(): void
    {
        [$reporter, $post] = $this->memberWithPublishedPost();
        Sanctum::actingAs($reporter);
        $payload = ['reason_code' => 'spam'];

        $first = $this->report($post->id, $payload, strtoupper(self::KEY))->assertCreated();
        $second = $this->report($post->id, $payload, self::KEY)->assertCreated();

        $this->assertSame($first->json('id'), $second->json('id'));
        $this->assertSame(self::KEY, PostReport::query()->find($first->json('id'))->idempotency_key);
        $this->assertSame(1, PostReport::query()->count());
    }

    public function test_invisible_post_keeps_404_even_with_key(): void
    {
        [, , , $post] = $this->publishedCommunityPost();
        [$groupB] = $this->publishedCommunityPost();
        $outsider = User::factory()->create();
        $this->addMemberToGroup($groupB, $outsider);
        Sanctum::actingAs($outsider);

        $this->report($post->id, ['reason_code' => 'spam'], self::KEY)->assertNotFound();
        $this->assertSame(0, PostReport::query()->count());
    }

    public function test_unpublished_post_keeps_403_even_with_key(): void
    {
        [$group, $author] = $this->activeGroupTriple();
        $pending = app(CreateCommunityPostService::class)->execute(
            $group,
            $author,
            $this->postCategory->id,
            'Pendiente',
            'Texto',
        );
        app(SubmitPostService::class)->execute($pending, $author);
        Sanctum::actingAs($author);

        $this->report($pending->id, ['reason_code' => 'spam'], self::KEY)->assertForbidden();
        $this->assertSame(0, PostReport::query()->count());
    }

    public function test_unauthenticated_keeps_401(): void
    {
        [, , , $post] = $this->publishedCommunityPost();

        $this->report($post->id, ['reason_code' => 'spam'], self::KEY)->assertUnauthorized();
        $this->postJson("/api/v1/posts/{$post->id}/reports", ['reason_code' => 'spam'])->assertUnauthorized();
    }

    public function test_replay_after_resolve_keeps_admin_state_and_creation_json(): void
    {
        [$reporter, $post, $admin] = $this->memberWithPublishedPostAndAdmin();
        Sanctum::actingAs($reporter);
        $created = $this->report($post->id, ['reason_code' => 'spam', 'details' => 'Uno'], self::KEY)->assertCreated();
        $report = PostReport::query()->findOrFail($created->json('id'));

        app(TransitionPostReportService::class)->execute(
            $report,
            $admin,
            PostReportStatus::Resolved,
            'Fundamento',
        );
        $eventsBefore = PostModerationEvent::query()->where('post_id', $post->id)->count();
        $resolved = $report->fresh();

        $replay = $this->report($post->id, ['reason_code' => 'spam', 'details' => 'Uno'], self::KEY);
        $replay->assertCreated()->assertExactJson([
            'id' => $report->id,
            'status' => PostReportStatus::Open->value,
        ]);

        $fresh = $report->fresh();
        $this->assertSame(PostReportStatus::Resolved, $fresh->status);
        $this->assertSame($resolved->resolved_by, $fresh->resolved_by);
        $this->assertTrue($resolved->resolved_at->eq($fresh->resolved_at));
        $this->assertSame('Fundamento', $fresh->resolution_note);
        $this->assertSame($eventsBefore, PostModerationEvent::query()->where('post_id', $post->id)->count());
        $this->assertSame(1, PostReport::query()->count());
    }

    public function test_replay_after_reviewing_does_not_reopen_or_audit(): void
    {
        [$reporter, $post, $admin] = $this->memberWithPublishedPostAndAdmin();
        Sanctum::actingAs($reporter);
        $created = $this->report($post->id, ['reason_code' => 'spam'], self::KEY)->assertCreated();
        $report = PostReport::query()->findOrFail($created->json('id'));

        app(TransitionPostReportService::class)->execute($report, $admin, PostReportStatus::Reviewing);
        $eventsBefore = PostModerationEvent::query()->where('post_id', $post->id)->count();

        $this->report($post->id, ['reason_code' => 'spam'], self::KEY)
            ->assertCreated()
            ->assertJsonPath('status', PostReportStatus::Open->value);

        $fresh = $report->fresh();
        $this->assertSame(PostReportStatus::Reviewing, $fresh->status);
        $this->assertSame($admin->id, $fresh->resolved_by);
        $this->assertNull($fresh->resolved_at);
        $this->assertNull($fresh->resolution_note);
        $this->assertSame($eventsBefore, PostModerationEvent::query()->where('post_id', $post->id)->count());
    }

    /**
     * @return array{0: User, 1: Post}
     */
    private function memberWithPublishedPost(): array
    {
        [$group, , , $post] = $this->publishedCommunityPost();
        $reporter = User::factory()->create();
        $this->addMemberToGroup($group, $reporter);

        return [$reporter, $post];
    }

    /**
     * @return array{0: NeighborhoodGroup, 1: User, 2: Post}
     */
    private function memberOnGroupWithPost(): array
    {
        [$group, , , $post] = $this->publishedCommunityPost();
        $reporter = User::factory()->create();
        $this->addMemberToGroup($group, $reporter);

        return [$group, $reporter, $post];
    }

    /**
     * @return array{0: User, 1: Post, 2: User}
     */
    private function memberWithPublishedPostAndAdmin(): array
    {
        [$group, , , $post] = $this->publishedCommunityPost();
        $reporter = User::factory()->create();
        $this->addMemberToGroup($group, $reporter);
        $admin = $this->municipalAdministratorFor($group->municipality);

        return [$reporter, $post, $admin];
    }

    /**
     * @param  array<string, mixed>  $payload
     */
    private function report(int $postId, array $payload, string $key): TestResponse
    {
        return $this->withHeader(PostReportIdempotency::HEADER, $key)
            ->postJson("/api/v1/posts/{$postId}/reports", $payload);
    }
}
