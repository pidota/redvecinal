<?php

namespace Tests\Feature\Posts;

use App\Domains\Posts\Enums\PostReportStatus;
use App\Domains\Posts\Exceptions\PostReportIdempotencyException;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostComment;
use App\Domains\Posts\Models\PostReport;
use App\Domains\Posts\Services\ReportPostService;
use App\Domains\Posts\Support\PostReportIdempotency;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PDOException;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class PostReportIdempotencyRaceTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    private const KEY = '550e8400-e29b-41d4-a716-446655440000';

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_unique_collision_with_same_payload_replays_existing_row(): void
    {
        [, $author, , $post] = $this->publishedCommunityPost();
        $fingerprint = PostReportIdempotency::fingerprint($post->id, 'spam', 'Uno');
        $existing = PostReport::query()->create([
            'post_id' => $post->id,
            'municipality_id' => $post->municipality_id,
            'reporter_id' => $author->id,
            'reason_code' => 'spam',
            'details' => 'Uno',
            'status' => PostReportStatus::Open,
            'idempotency_key' => self::KEY,
            'payload_fingerprint' => $fingerprint,
        ]);

        $service = new class extends ReportPostService
        {
            private bool $skipFirstLookup = true;

            protected function findKeyedReportForUpdate(int $reporterId, string $idempotencyKey): ?PostReport
            {
                if ($this->skipFirstLookup) {
                    $this->skipFirstLookup = false;

                    return null;
                }

                return parent::findKeyedReportForUpdate($reporterId, $idempotencyKey);
            }
        };

        $result = $service->execute($author, 'spam', $post, null, 'Uno', self::KEY);

        $this->assertSame($existing->id, $result->id);
        $this->assertSame(1, PostReport::query()->where('idempotency_key', self::KEY)->count());
        $this->assertSame(PostReportStatus::Open, $existing->fresh()->status);
    }

    public function test_unique_collision_with_different_payload_conflicts(): void
    {
        [, $author, , $post] = $this->publishedCommunityPost();
        PostReport::query()->create([
            'post_id' => $post->id,
            'municipality_id' => $post->municipality_id,
            'reporter_id' => $author->id,
            'reason_code' => 'spam',
            'details' => 'Uno',
            'status' => PostReportStatus::Open,
            'idempotency_key' => self::KEY,
            'payload_fingerprint' => PostReportIdempotency::fingerprint($post->id, 'spam', 'Uno'),
        ]);

        $service = new class extends ReportPostService
        {
            private bool $skipFirstLookup = true;

            protected function findKeyedReportForUpdate(int $reporterId, string $idempotencyKey): ?PostReport
            {
                if ($this->skipFirstLookup) {
                    $this->skipFirstLookup = false;

                    return null;
                }

                return parent::findKeyedReportForUpdate($reporterId, $idempotencyKey);
            }
        };

        try {
            $service->execute($author, 'inappropriate', $post, null, 'Otro', self::KEY);
            $this->fail('Debe conflictuar el payload distinto.');
        } catch (PostReportIdempotencyException $exception) {
            $this->assertSame(409, $exception->httpStatus);
        }

        $this->assertSame(1, PostReport::query()->count());
        $this->assertSame('spam', PostReport::query()->first()->reason_code);
    }

    public function test_unrelated_query_exception_is_not_treated_as_idempotency(): void
    {
        [, $author, , $post] = $this->publishedCommunityPost();
        $before = PostReport::query()->count();

        $service = new class extends ReportPostService
        {
            protected function insertOpenReport(
                User $reporter,
                string $reasonCode,
                ?Post $post,
                ?PostComment $comment,
                ?string $details,
                ?string $idempotencyKey,
                ?string $fingerprint,
            ): PostReport {
                $previous = new PDOException(
                    'SQLSTATE[23000]: Integrity constraint violation: 1452 Cannot add or update a child row: a foreign key constraint fails',
                    1452,
                );
                $previous->errorInfo = [
                    '23000',
                    1452,
                    'Cannot add or update a child row: a foreign key constraint fails',
                ];

                throw new QueryException('sqlite', 'insert into "post_reports"', [], $previous);
            }
        };

        try {
            $service->execute($author, 'spam', $post, null, null, self::KEY);
            $this->fail('Debe relanzar el error de clave foránea.');
        } catch (QueryException $exception) {
            $this->assertSame(1452, $exception->errorInfo[1] ?? null);
        }

        $this->assertSame($before, PostReport::query()->count());
    }
}
