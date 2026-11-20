<?php

namespace Tests\Feature\Posts;

use App\Domains\Posts\Enums\PostReportStatus;
use App\Domains\Posts\Models\PostModerationEvent;
use App\Domains\Posts\Models\PostReport;
use App\Domains\Posts\Services\ReportPostService;
use App\Domains\Posts\Services\TransitionPostReportService;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\DatabaseTruncation;
use Illuminate\Process\ProcessPoolResults;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Process;
use Tests\Concerns\CreatesPostFixtures;
use Tests\Concurrency\PostReportIdempotencyBarrier;
use Tests\TestCase;

/**
 * Concurrencia real: dos procesos PHP, dos conexiones MySQL 8.4, barrera de archivos.
 * SQLite: se omite. CI: phpunit.mysql.idempotency.xml (workflow_dispatch).
 * No se afirma que InnoDB pasó hasta ver resultados de GitHub Actions.
 */
class PostReportIdempotencyMysqlConcurrencyTest extends TestCase
{
    use CreatesPostFixtures, DatabaseTruncation;

    private const KEY_A = '550e8400-e29b-41d4-a716-446655440000';

    private const KEY_B = '123e4567-e89b-42d3-a456-426614174000';

    /**
     * @var array<int, string>
     */
    protected array $connectionsToTransact = [];

    protected function shouldSeed(): bool
    {
        return false;
    }

    protected function beforeTruncatingDatabase(): void
    {
        DB::disconnect();
    }

    protected function afterTruncatingDatabase(): void
    {
        DB::disconnect();
    }

    protected function tearDown(): void
    {
        DB::disconnect();

        parent::tearDown();
    }

    protected function setUp(): void
    {
        parent::setUp();

        if (DB::connection()->getDriverName() !== 'mysql') {
            $this->markTestSkipped('Concurrencia real de reportes requiere MySQL 8.4 aislado (red_vecinal_testing).');
        }

        $this->assertSame('testing', config('app.env'));
        $this->assertSame('mysql', (string) config('database.default'));
        $this->assertSame('red_vecinal_testing', (string) config('database.connections.mysql.database'));
        $this->assertSame('127.0.0.1', (string) config('database.connections.mysql.host'));

        $version = (string) (DB::selectOne('select version() as v')->v ?? '');
        $this->assertTrue(
            str_starts_with($version, '8.4.'),
            'Se aborta: se requiere MySQL 8.4, versión efectiva: '.$version
        );

        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seedPostsBasics();
    }

    public function test_a_parallel_same_key_same_payload_single_row_same_id(): void
    {
        [$group, , , $post] = $this->publishedCommunityPost();
        $reporter = User::factory()->create();
        $this->addMemberToGroup($group, $reporter);

        $base = $this->workerEnv($post->id, $reporter->id, self::KEY_A, 'spam', 'Uno');
        $parsed = $this->runBarrierPair($base, $base);

        $this->assertNoUnclassifiedServerError($parsed);
        $this->assertSame(
            1,
            PostReport::query()->where('reporter_id', $reporter->id)->where('idempotency_key', self::KEY_A)->count()
        );
        $this->assertNoRemainingLockErrors($parsed);

        $okIds = $this->okIds($parsed);
        $this->assertCount(2, $okIds, $this->combined($parsed));
        $this->assertSame($okIds[0], $okIds[1]);
    }

    public function test_b_parallel_same_key_different_payload_conflicts(): void
    {
        [$group, , , $post] = $this->publishedCommunityPost();
        $reporter = User::factory()->create();
        $this->addMemberToGroup($group, $reporter);

        $envA = $this->workerEnv($post->id, $reporter->id, self::KEY_A, 'spam', 'Uno');
        $envB = $this->workerEnv($post->id, $reporter->id, self::KEY_A, 'inappropriate', 'Dos');
        $parsed = $this->runBarrierPair($envA, $envB);

        $this->assertNoUnclassifiedServerError($parsed);
        $this->assertSame(1, PostReport::query()->where('reporter_id', $reporter->id)->count());
        $this->assertNoRemainingLockErrors($parsed);
        $row = PostReport::query()->where('reporter_id', $reporter->id)->first();
        $this->assertNotNull($row);
        $this->assertContains($row->reason_code, ['spam', 'inappropriate']);

        $oks = $this->okIds($parsed);
        $conflicts = $this->errCodes($parsed, 409);
        $this->assertCount(1, $oks, $this->combined($parsed));
        $this->assertCount(1, $conflicts, $this->combined($parsed));
        $this->assertSame($row->id, $oks[0]);
    }

    public function test_c_parallel_distinct_keys_create_two_reports(): void
    {
        [$group, , , $post] = $this->publishedCommunityPost();
        $reporter = User::factory()->create();
        $this->addMemberToGroup($group, $reporter);

        $envA = $this->workerEnv($post->id, $reporter->id, self::KEY_A, 'spam', 'Uno');
        $envB = $this->workerEnv($post->id, $reporter->id, self::KEY_B, 'spam', 'Uno');
        $parsed = $this->runBarrierPair($envA, $envB);

        $this->assertNoUnclassifiedServerError($parsed);
        $this->assertNoRemainingLockErrors($parsed);
        $okIds = $this->okIds($parsed);
        $this->assertCount(2, $okIds, $this->combined($parsed));
        $this->assertNotSame($okIds[0], $okIds[1]);
        $this->assertSame(2, PostReport::query()->where('reporter_id', $reporter->id)->count());
    }

    public function test_d_same_key_different_users_are_isolated(): void
    {
        [$group, , , $post] = $this->publishedCommunityPost();
        $first = User::factory()->create();
        $second = User::factory()->create();
        $this->addMemberToGroup($group, $first);
        $this->addMemberToGroup($group, $second);

        $envA = $this->workerEnv($post->id, $first->id, self::KEY_A, 'spam', 'Uno');
        $envB = $this->workerEnv($post->id, $second->id, self::KEY_A, 'spam', 'Uno');
        $parsed = $this->runBarrierPair($envA, $envB);

        $this->assertNoUnclassifiedServerError($parsed);
        $this->assertNoRemainingLockErrors($parsed);
        $okIds = $this->okIds($parsed);
        $this->assertCount(2, $okIds, $this->combined($parsed));
        $this->assertNotSame($okIds[0], $okIds[1]);
        $this->assertSame(1, PostReport::query()->where('reporter_id', $first->id)->count());
        $this->assertSame(1, PostReport::query()->where('reporter_id', $second->id)->count());
        $this->assertSame(self::KEY_A, PostReport::query()->where('reporter_id', $first->id)->value('idempotency_key'));
        $this->assertSame(self::KEY_A, PostReport::query()->where('reporter_id', $second->id)->value('idempotency_key'));
    }

    public function test_e_replay_after_commit_keeps_admin_state(): void
    {
        [$group, , , $post] = $this->publishedCommunityPost();
        $reporter = User::factory()->create();
        $this->addMemberToGroup($group, $reporter);
        $admin = $this->municipalAdministratorFor($group->municipality);

        $created = app(ReportPostService::class)->execute($reporter, 'spam', $post, null, 'Uno', self::KEY_A);
        app(TransitionPostReportService::class)->execute(
            $created,
            $admin,
            PostReportStatus::Resolved,
            'Fundamento',
        );
        $eventsBefore = PostModerationEvent::query()->where('post_id', $post->id)->count();
        $resolved = $created->fresh();

        $env = $this->workerEnv($post->id, $reporter->id, self::KEY_A, 'spam', 'Uno');
        $parsed = $this->runBarrierPair($env, $env);

        $this->assertNoUnclassifiedServerError($parsed);
        $this->assertNoRemainingLockErrors($parsed);
        $okIds = $this->okIds($parsed);
        $this->assertCount(2, $okIds, $this->combined($parsed));
        $this->assertSame($created->id, $okIds[0]);
        $this->assertSame($created->id, $okIds[1]);
        $this->assertSame(1, PostReport::query()->count());

        $fresh = $created->fresh();
        $this->assertSame(PostReportStatus::Resolved, $fresh->status);
        $this->assertSame($resolved->resolved_by, $fresh->resolved_by);
        $this->assertTrue($resolved->resolved_at->eq($fresh->resolved_at));
        $this->assertSame('Fundamento', $fresh->resolution_note);
        $this->assertSame($eventsBefore, PostModerationEvent::query()->where('post_id', $post->id)->count());
    }

    public function test_f_lock_errors_are_classified_and_do_not_duplicate(): void
    {
        [$group, , , $post] = $this->publishedCommunityPost();
        $reporter = User::factory()->create();
        $this->addMemberToGroup($group, $reporter);

        $base = $this->workerEnv($post->id, $reporter->id, self::KEY_A, 'spam', 'Uno');
        $parsed = $this->runBarrierPair($base, $base);
        $combined = $this->combined($parsed);

        $this->assertSame(
            1,
            PostReport::query()->where('reporter_id', $reporter->id)->where('idempotency_key', self::KEY_A)->count(),
            $combined
        );

        foreach ($parsed as $outcome) {
            if (in_array($outcome['err'], [1213, 1205], true)) {
                $this->assertNull($outcome['ok'], 'Un 1213/1205 no debe publicarse como OK/replay. '.$combined);
            }
        }

        $this->assertStringNotContainsString('ERR:500', $combined, $combined);
        $this->assertNoRemainingLockErrors($parsed);
        $okIds = $this->okIds($parsed);
        $this->assertCount(2, $okIds, 'Disponibilidad: los reintentos internos deben absorber 1213/1205. '.$combined);
        $this->assertSame($okIds[0], $okIds[1]);
    }

    /**
     * @param  array<string, string>  $envA
     * @param  array<string, string>  $envB
     * @return array<string, array{ok: ?int, err: ?int, raw: string}>
     */
    private function runBarrierPair(array $envA, array $envB): array
    {
        $dir = PostReportIdempotencyBarrier::createDirectory();
        $script = base_path('tests/Concurrency/post_report_idempotency_worker.php');
        $command = escapeshellarg(PHP_BINARY).' '.escapeshellarg($script);

        $envA = array_merge($envA, [
            'PR_BARRIER_DIR' => $dir,
            'PR_WORKER_SLOT' => 'a',
            'PR_BARRIER_TIMEOUT_MS' => (string) PostReportIdempotencyBarrier::DEFAULT_TIMEOUT_MS,
        ]);
        $envB = array_merge($envB, [
            'PR_BARRIER_DIR' => $dir,
            'PR_WORKER_SLOT' => 'b',
            'PR_BARRIER_TIMEOUT_MS' => (string) PostReportIdempotencyBarrier::DEFAULT_TIMEOUT_MS,
        ]);

        $invoked = null;
        try {
            $invoked = Process::pool(function ($pool) use ($command, $envA, $envB) {
                $pool->as('a')->path(base_path())->env($envA)->timeout(120)->command($command);
                $pool->as('b')->path(base_path())->env($envB)->timeout(120)->command($command);
            })->start();

            PostReportIdempotencyBarrier::waitUntilReady($dir, ['a', 'b']);
            PostReportIdempotencyBarrier::release($dir);

            $results = $invoked->wait();
            $this->finalizeWorkerPool($results);

            return [
                'a' => $this->parseWorkerOutput($results['a']->output()),
                'b' => $this->parseWorkerOutput($results['b']->output()),
            ];
        } catch (\Throwable $e) {
            $invoked?->stop(3);
            throw $e;
        } finally {
            PostReportIdempotencyBarrier::cleanup($dir);
        }
    }

    /**
     * @return array<string, string>
     */
    private function workerEnv(int $postId, int $userId, string $key, string $reason, ?string $details): array
    {
        $connection = config('database.default');
        $db = config("database.connections.{$connection}");

        $env = [
            'APP_ENV' => 'testing',
            'APP_KEY' => (string) config('app.key'),
            'DB_CONNECTION' => (string) $connection,
            'DB_HOST' => (string) ($db['host'] ?? '127.0.0.1'),
            'DB_PORT' => (string) ($db['port'] ?? '3306'),
            'DB_DATABASE' => (string) ($db['database'] ?? ''),
            'DB_USERNAME' => (string) ($db['username'] ?? ''),
            'DB_PASSWORD' => (string) ($db['password'] ?? ''),
            'PATH' => (string) (getenv('PATH') ?: ''),
            'HOME' => (string) (getenv('HOME') ?: ''),
            'TMPDIR' => (string) (getenv('TMPDIR') ?: sys_get_temp_dir()),
            'PR_POST_ID' => (string) $postId,
            'PR_USER_ID' => (string) $userId,
            'PR_IDEMPOTENCY_KEY' => $key,
            'PR_REASON_CODE' => $reason,
        ];

        if ($details !== null) {
            $env['PR_DETAILS'] = $details;
        }

        return $env;
    }

    /**
     * @return array{ok: ?int, err: ?int, raw: string}
     */
    private function parseWorkerOutput(string $output): array
    {
        if (preg_match('/^OK:(\d+)/m', $output, $match) === 1) {
            return ['ok' => (int) $match[1], 'err' => null, 'raw' => $output];
        }
        if (preg_match('/^ERR:(\d+)/m', $output, $match) === 1) {
            return ['ok' => null, 'err' => (int) $match[1], 'raw' => $output];
        }

        return ['ok' => null, 'err' => null, 'raw' => $output];
    }

    /**
     * @param  array<string, array{ok: ?int, err: ?int, raw: string}>  $parsed
     * @return list<int>
     */
    private function okIds(array $parsed): array
    {
        $ids = [];
        foreach ($parsed as $outcome) {
            if ($outcome['ok'] !== null) {
                $ids[] = $outcome['ok'];
            }
        }

        return $ids;
    }

    /**
     * @param  array<string, array{ok: ?int, err: ?int, raw: string}>  $parsed
     * @return list<int>
     */
    private function errCodes(array $parsed, int $code): array
    {
        $codes = [];
        foreach ($parsed as $outcome) {
            if ($outcome['err'] === $code) {
                $codes[] = $code;
            }
        }

        return $codes;
    }

    /**
     * @param  array<string, array{ok: ?int, err: ?int, raw: string}>  $parsed
     * @return list<int>
     */
    private function lockErrors(array $parsed): array
    {
        $codes = [];
        foreach ($parsed as $outcome) {
            if (in_array($outcome['err'], [1213, 1205], true)) {
                $codes[] = $outcome['err'];
            }
        }

        return $codes;
    }

    /**
     * @param  array<string, array{ok: ?int, err: ?int, raw: string}>  $parsed
     */
    private function combined(array $parsed): string
    {
        return trim($parsed['a']['raw'].' | '.$parsed['b']['raw']);
    }

    /**
     * @param  array<string, array{ok: ?int, err: ?int, raw: string}>  $parsed
     */
    private function assertNoUnclassifiedServerError(array $parsed): void
    {
        $this->assertStringNotContainsString('ERR:500', $this->combined($parsed), $this->combined($parsed));
        $this->assertStringNotContainsString('ERR:2:', $this->combined($parsed), $this->combined($parsed));
    }

    /**
     * @param  array<string, array{ok: ?int, err: ?int, raw: string}>  $parsed
     */
    private function assertNoRemainingLockErrors(array $parsed): void
    {
        $this->assertSame(
            [],
            $this->lockErrors($parsed),
            'Disponibilidad fallida: 1213/1205 tras reintentos internos. '.$this->combined($parsed)
        );
    }

    private function finalizeWorkerPool(ProcessPoolResults $results): void
    {
        foreach ($results as $label => $result) {
            $this->assertSame(
                0,
                $result->exitCode(),
                $label.' worker exit='.$result->exitCode().' stderr='.trim($result->errorOutput())
            );
        }

        DB::disconnect();
    }
}
