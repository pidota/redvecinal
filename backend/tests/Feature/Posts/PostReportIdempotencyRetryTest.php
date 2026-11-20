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
use Illuminate\Database\DeadlockException;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use PDOException;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class PostReportIdempotencyRetryTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    private const KEY = '550e8400-e29b-41d4-a716-446655440000';

    protected function setUp(): void
    {
        parent::setUp();
        $this->seedPostsBasics();
    }

    public function test_transient_deadlock_retries_and_inserts_once(): void
    {
        [, $author, , $post] = $this->publishedCommunityPost();
        $service = $this->serviceThatFailsInsertsThenSucceeds(2, 1213, '40001', 'Deadlock found when trying to get lock');

        $created = $service->execute($author, 'spam', $post, null, 'Uno', self::KEY);

        $this->assertSame(3, $service->insertAttempts);
        $this->assertSame(1, PostReport::query()->where('reporter_id', $author->id)->count());
        $this->assertSame($created->id, PostReport::query()->first()->id);
        $this->assertSame(self::KEY, $created->idempotency_key);
    }

    public function test_transient_lock_wait_retries_and_inserts_once(): void
    {
        [, $author, , $post] = $this->publishedCommunityPost();
        $service = $this->serviceThatFailsInsertsThenSucceeds(2, 1205, 'HY000', 'Lock wait timeout exceeded');

        $created = $service->execute($author, 'spam', $post, null, 'Uno', self::KEY);

        $this->assertSame(3, $service->insertAttempts);
        $this->assertSame(1, PostReport::query()->count());
        $this->assertSame($created->id, PostReport::query()->value('id'));
    }

    public function test_exhausted_transient_retries_are_not_success(): void
    {
        [, $author, , $post] = $this->publishedCommunityPost();
        $before = PostReport::query()->count();
        $service = $this->serviceThatFailsInsertsThenSucceeds(99, 1213, '40001', 'Deadlock found when trying to get lock');

        try {
            $service->execute($author, 'spam', $post, null, 'Uno', self::KEY);
            $this->fail('El agotamiento de 1213 no debe convertirse en éxito.');
        } catch (QueryException|DeadlockException $exception) {
            $this->assertTrue(PostReportIdempotency::isTransientLockError($exception));
        }

        $this->assertSame(PostReportIdempotency::TRANSIENT_ATTEMPTS, $service->insertAttempts);
        $this->assertSame($before, PostReport::query()->count());
    }

    public function test_payload_conflict_is_not_retried(): void
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
            public int $lookups = 0;

            public int $inserts = 0;

            protected function findKeyedReport(int $reporterId, string $idempotencyKey): ?PostReport
            {
                $this->lookups++;

                return parent::findKeyedReport($reporterId, $idempotencyKey);
            }

            protected function insertOpenReport(
                User $reporter,
                string $reasonCode,
                ?Post $post,
                ?PostComment $comment,
                ?string $details,
                ?string $idempotencyKey,
                ?string $fingerprint,
            ): PostReport {
                $this->inserts++;

                return parent::insertOpenReport($reporter, $reasonCode, $post, $comment, $details, $idempotencyKey, $fingerprint);
            }

            protected function pauseBeforeTransientRetry(int $attempt): void {}
        };

        try {
            $service->execute($author, 'inappropriate', $post, null, 'Otro', self::KEY);
            $this->fail('Debe conflictuar sin reintentar.');
        } catch (PostReportIdempotencyException $exception) {
            $this->assertSame(409, $exception->httpStatus);
        }

        $this->assertSame(1, $service->lookups);
        $this->assertSame(0, $service->inserts);
        $this->assertSame(1, PostReport::query()->count());
        $this->assertSame('spam', PostReport::query()->value('reason_code'));
    }

    public function test_unknown_sql_error_is_not_retried(): void
    {
        [, $author, , $post] = $this->publishedCommunityPost();
        $before = PostReport::query()->count();
        $service = new class extends ReportPostService
        {
            public int $inserts = 0;

            protected function insertOpenReport(
                User $reporter,
                string $reasonCode,
                ?Post $post,
                ?PostComment $comment,
                ?string $details,
                ?string $idempotencyKey,
                ?string $fingerprint,
            ): PostReport {
                $this->inserts++;
                $previous = new PDOException('SQLSTATE[HY000]: General error: 9999 boom', 9999);
                $previous->errorInfo = ['HY000', 9999, 'boom'];

                throw new QueryException('mysql', 'insert into post_reports', [], $previous);
            }

            protected function pauseBeforeTransientRetry(int $attempt): void {}
        };

        try {
            $service->execute($author, 'spam', $post, null, 'Uno', self::KEY);
            $this->fail('Un error SQL desconocido no se reintenta.');
        } catch (QueryException $exception) {
            $this->assertSame(9999, $exception->errorInfo[1] ?? null);
        }

        $this->assertSame(1, $service->inserts);
        $this->assertSame($before, PostReport::query()->count());
    }

    public function test_legacy_request_without_key_is_not_retried(): void
    {
        [, $author, , $post] = $this->publishedCommunityPost();
        $service = new class extends ReportPostService
        {
            public int $inserts = 0;

            protected function insertOpenReport(
                User $reporter,
                string $reasonCode,
                ?Post $post,
                ?PostComment $comment,
                ?string $details,
                ?string $idempotencyKey,
                ?string $fingerprint,
            ): PostReport {
                $this->inserts++;
                $previous = new PDOException('SQLSTATE[40001]: Serialization failure: 1213 Deadlock found when trying to get lock', 1213);
                $previous->errorInfo = ['40001', 1213, 'Deadlock found when trying to get lock'];

                throw new QueryException('mysql', 'insert into post_reports', [], $previous);
            }

            protected function pauseBeforeTransientRetry(int $attempt): void {}
        };

        try {
            $service->execute($author, 'spam', $post, null, 'Uno', null);
            $this->fail('Legacy no debe reintentar 1213.');
        } catch (QueryException $exception) {
            $this->assertSame(1213, $exception->errorInfo[1] ?? null);
        }

        $this->assertSame(1, $service->inserts);
    }

    public function test_rollback_between_transient_attempts_leaves_no_partial_row(): void
    {
        [, $author, , $post] = $this->publishedCommunityPost();
        $service = new class extends ReportPostService
        {
            public int $insertAttempts = 0;

            /** @var list<int> */
            public array $countsAfterFailure = [];

            protected function insertOpenReport(
                User $reporter,
                string $reasonCode,
                ?Post $post,
                ?PostComment $comment,
                ?string $details,
                ?string $idempotencyKey,
                ?string $fingerprint,
            ): PostReport {
                $this->insertAttempts++;
                if ($this->insertAttempts === 1) {
                    PostReport::query()->create([
                        'post_id' => $post?->id,
                        'municipality_id' => $post?->municipality_id,
                        'reporter_id' => $reporter->id,
                        'reason_code' => $reasonCode,
                        'details' => $details,
                        'status' => PostReportStatus::Open,
                        'idempotency_key' => '123e4567-e89b-42d3-a456-426614174000',
                        'payload_fingerprint' => 'x',
                    ]);
                    $previous = new PDOException('SQLSTATE[40001]: Serialization failure: 1213 Deadlock found when trying to get lock', 1213);
                    $previous->errorInfo = ['40001', 1213, 'Deadlock found when trying to get lock'];

                    throw new QueryException('mysql', 'insert into post_reports', [], $previous);
                }

                return parent::insertOpenReport($reporter, $reasonCode, $post, $comment, $details, $idempotencyKey, $fingerprint);
            }

            protected function pauseBeforeTransientRetry(int $attempt): void
            {
                $this->countsAfterFailure[] = PostReport::query()->count();
            }
        };

        $created = $service->execute($author, 'spam', $post, null, 'Uno', self::KEY);

        $this->assertSame([0], $service->countsAfterFailure);
        $this->assertSame(1, PostReport::query()->where('idempotency_key', self::KEY)->count());
        $this->assertSame($created->id, PostReport::query()->where('idempotency_key', self::KEY)->value('id'));
        $this->assertSame(0, PostReport::query()->where('idempotency_key', '123e4567-e89b-42d3-a456-426614174000')->count());
    }

    /**
     * @return ReportPostService&object{insertAttempts: int}
     */
    private function serviceThatFailsInsertsThenSucceeds(int $failures, int $driverCode, string $sqlState, string $message): ReportPostService
    {
        return new class($failures, $driverCode, $sqlState, $message) extends ReportPostService
        {
            public int $insertAttempts = 0;

            public function __construct(
                private readonly int $failures,
                private readonly int $driverCode,
                private readonly string $sqlState,
                private readonly string $sqlMessage,
            ) {}

            protected function insertOpenReport(
                User $reporter,
                string $reasonCode,
                ?Post $post,
                ?PostComment $comment,
                ?string $details,
                ?string $idempotencyKey,
                ?string $fingerprint,
            ): PostReport {
                $this->insertAttempts++;
                if ($this->insertAttempts <= $this->failures) {
                    $previous = new PDOException($this->sqlMessage, $this->driverCode);
                    $previous->errorInfo = [$this->sqlState, $this->driverCode, $this->sqlMessage];

                    throw new QueryException('mysql', 'insert into post_reports', [], $previous);
                }

                return parent::insertOpenReport($reporter, $reasonCode, $post, $comment, $details, $idempotencyKey, $fingerprint);
            }

            protected function pauseBeforeTransientRetry(int $attempt): void {}
        };
    }
}
