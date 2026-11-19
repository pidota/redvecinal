<?php

namespace Tests\Feature\Posts;

use App\Domains\Posts\Enums\PostReportStatus;
use App\Domains\Posts\Models\PostReport;
use App\Domains\Posts\Services\CreateCommunityPostService;
use App\Domains\Posts\Services\ReportPostService;
use App\Domains\Posts\Services\SubmitPostService;
use App\Domains\Posts\Support\PostReportIdempotency;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Schema;
use Laravel\Sanctum\Sanctum;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class PostReportIdempotencySchemaTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_additive_migration_adds_nullable_columns_and_unique_index(): void
    {
        $this->assertTrue(Schema::hasColumn('post_reports', 'idempotency_key'));
        $this->assertTrue(Schema::hasColumn('post_reports', 'payload_fingerprint'));

        $columns = collect(Schema::getColumns('post_reports'))->keyBy('name');
        $this->assertTrue($columns['idempotency_key']['nullable']);
        $this->assertTrue($columns['payload_fingerprint']['nullable']);

        $unique = collect(Schema::getIndexes('post_reports'))
            ->firstWhere('name', 'post_reports_reporter_idempotency_unique');

        $this->assertIsArray($unique);
        $this->assertTrue($unique['unique']);
        $this->assertSame(['reporter_id', 'idempotency_key'], $unique['columns']);

        $reporterPostUnique = collect(Schema::getIndexes('post_reports'))
            ->contains(function (array $index): bool {
                return ($index['unique'] ?? false)
                    && $index['columns'] === ['reporter_id', 'post_id'];
            });
        $this->assertFalse($reporterPostUnique);
    }

    public function test_legacy_reports_without_key_remain_nullable(): void
    {
        [, $author, , $post] = $this->publishedCommunityPost();

        $record = app(ReportPostService::class)->execute($author, 'spam', $post, null, 'Detalle');

        $this->assertNull($record->idempotency_key);
        $this->assertNull($record->payload_fingerprint);
        $this->assertDatabaseHas('post_reports', [
            'id' => $record->id,
            'reporter_id' => $author->id,
            'post_id' => $post->id,
            'idempotency_key' => null,
            'payload_fingerprint' => null,
            'status' => PostReportStatus::Open->value,
        ]);
    }

    public function test_same_user_can_create_two_reports_without_key_on_same_post(): void
    {
        [, $author, , $post] = $this->publishedCommunityPost();
        $service = app(ReportPostService::class);

        $first = $service->execute($author, 'spam', $post);
        $second = $service->execute($author, 'spam', $post);

        $this->assertNotSame($first->id, $second->id);
        $this->assertSame(2, PostReport::query()
            ->where('reporter_id', $author->id)
            ->where('post_id', $post->id)
            ->whereNull('idempotency_key')
            ->count());
    }

    public function test_sqlite_allows_multiple_null_idempotency_keys_for_same_reporter(): void
    {
        $this->assertSame('sqlite', Schema::getConnection()->getDriverName());

        [, $author, , $post] = $this->publishedCommunityPost();

        PostReport::query()->create($this->reportAttributes($post, $author, ['idempotency_key' => null]));
        PostReport::query()->create($this->reportAttributes($post, $author, ['idempotency_key' => null]));
        PostReport::query()->create($this->reportAttributes($post, $author, ['idempotency_key' => null]));

        $this->assertSame(3, PostReport::query()
            ->where('reporter_id', $author->id)
            ->whereNull('idempotency_key')
            ->count());
    }

    public function test_same_user_can_store_two_distinct_keys_on_the_same_post(): void
    {
        [, $author, , $post] = $this->publishedCommunityPost();
        $firstKey = '550e8400-e29b-41d4-a716-446655440000';
        $secondKey = '123e4567-e89b-42d3-a456-426614174000';

        PostReport::query()->create($this->reportAttributes($post, $author, [
            'idempotency_key' => $firstKey,
        ]));
        PostReport::query()->create($this->reportAttributes($post, $author, [
            'idempotency_key' => $secondKey,
        ]));

        $this->assertSame(2, PostReport::query()
            ->where('reporter_id', $author->id)
            ->where('post_id', $post->id)
            ->count());
    }

    public function test_unique_constraint_rejects_same_reporter_and_key(): void
    {
        [, $author, , $post] = $this->publishedCommunityPost();
        $key = '550e8400-e29b-41d4-a716-446655440000';

        PostReport::query()->create($this->reportAttributes($post, $author, [
            'idempotency_key' => $key,
        ]));

        $this->expectException(QueryException::class);
        $this->expectExceptionMessage('UNIQUE constraint failed');

        PostReport::query()->create($this->reportAttributes($post, $author, [
            'idempotency_key' => $key,
            'reason_code' => 'inappropriate',
        ]));
    }

    public function test_same_key_is_allowed_for_distinct_reporters(): void
    {
        [$group, $author, , $post] = $this->publishedCommunityPost();
        $other = User::factory()->create();
        $this->addMemberToGroup($group, $other);
        $key = '550e8400-e29b-41d4-a716-446655440000';

        PostReport::query()->create($this->reportAttributes($post, $author, [
            'idempotency_key' => $key,
        ]));
        PostReport::query()->create($this->reportAttributes($post, $other, [
            'idempotency_key' => $key,
        ]));

        $this->assertSame(2, PostReport::query()->where('idempotency_key', $key)->count());
    }

    public function test_payload_fingerprint_persists_canonical_hash(): void
    {
        [, $author, , $post] = $this->publishedCommunityPost();
        $fingerprint = PostReportIdempotency::fingerprint($post->id, 'spam', 'Detalle');

        $record = PostReport::query()->create($this->reportAttributes($post, $author, [
            'details' => 'Detalle',
            'idempotency_key' => '550e8400-e29b-41d4-a716-446655440000',
            'payload_fingerprint' => $fingerprint,
        ]));

        $this->assertSame($fingerprint, $record->fresh()->payload_fingerprint);
        $this->assertSame(64, strlen((string) $record->payload_fingerprint));
        $this->assertDatabaseHas('post_reports', [
            'id' => $record->id,
            'payload_fingerprint' => $fingerprint,
        ]);
    }

    public function test_model_fillable_and_casts_remain_compatible(): void
    {
        [, $author, , $post] = $this->publishedCommunityPost();

        $record = PostReport::query()->create($this->reportAttributes($post, $author, [
            'idempotency_key' => '550e8400-e29b-41d4-a716-446655440000',
            'payload_fingerprint' => str_repeat('a', 64),
        ]));

        $this->assertSame(PostReportStatus::Open, $record->status);
        $this->assertSame('550e8400-e29b-41d4-a716-446655440000', $record->idempotency_key);
        $this->assertTrue($record->isFillable('idempotency_key'));
        $this->assertTrue($record->isFillable('payload_fingerprint'));
        $this->assertSame($post->id, $record->post->id);
        $this->assertSame($author->id, $record->reporter->id);
    }

    public function test_public_api_still_creates_a_new_report_per_request(): void
    {
        [$group, , , $post] = $this->publishedCommunityPost();
        $reporter = User::factory()->create();
        $this->addMemberToGroup($group, $reporter);

        Sanctum::actingAs($reporter);

        $first = $this->postJson("/api/v1/posts/{$post->id}/reports", [
            'reason_code' => 'spam',
            'details' => 'Uno',
        ]);
        $second = $this->postJson("/api/v1/posts/{$post->id}/reports", [
            'reason_code' => 'spam',
            'details' => 'Uno',
        ]);

        $first->assertCreated()->assertExactJson([
            'id' => $first->json('id'),
            'status' => PostReportStatus::Open->value,
        ]);
        $second->assertCreated()->assertExactJson([
            'id' => $second->json('id'),
            'status' => PostReportStatus::Open->value,
        ]);
        $this->assertNotSame($first->json('id'), $second->json('id'));
        $this->assertSame(2, PostReport::query()->where('reporter_id', $reporter->id)->count());
    }

    public function test_client_cannot_assign_reporter_or_municipality_via_body(): void
    {
        [$group, , , $post] = $this->publishedCommunityPost();
        $reporter = User::factory()->create();
        $stranger = User::factory()->create();
        $this->addMemberToGroup($group, $reporter);

        Sanctum::actingAs($reporter);
        $response = $this->postJson("/api/v1/posts/{$post->id}/reports", [
            'reason_code' => 'spam',
            'reporter_id' => $stranger->id,
            'municipality_id' => 999999,
        ]);

        $response->assertCreated();
        $record = PostReport::query()->findOrFail($response->json('id'));
        $this->assertSame($reporter->id, $record->reporter_id);
        $this->assertSame($post->municipality_id, $record->municipality_id);
        $this->assertNotSame($stranger->id, $record->reporter_id);
    }

    public function test_authorization_contract_is_unchanged(): void
    {
        [$groupA, $author, , $post] = $this->publishedCommunityPost();
        [$groupB] = $this->publishedCommunityPost();
        $outsider = User::factory()->create();
        $this->addMemberToGroup($groupB, $outsider);

        $pending = app(CreateCommunityPostService::class)->execute(
            $groupA,
            $author,
            $this->postCategory->id,
            'Pendiente',
            'Texto',
        );
        app(SubmitPostService::class)->execute($pending, $author);

        $this->postJson("/api/v1/posts/{$post->id}/reports", ['reason_code' => 'spam'])
            ->assertUnauthorized();

        Sanctum::actingAs($outsider);
        $this->postJson("/api/v1/posts/{$post->id}/reports", ['reason_code' => 'spam'])
            ->assertNotFound();

        Sanctum::actingAs($author);
        $this->postJson("/api/v1/posts/{$pending->id}/reports", ['reason_code' => 'spam'])
            ->assertForbidden();
    }

    /**
     * @param  array<string, mixed>  $overrides
     * @return array<string, mixed>
     */
    private function reportAttributes($post, User $reporter, array $overrides = []): array
    {
        return array_merge([
            'post_id' => $post->id,
            'municipality_id' => $post->municipality_id,
            'reporter_id' => $reporter->id,
            'reason_code' => 'spam',
            'status' => PostReportStatus::Open,
        ], $overrides);
    }
}
