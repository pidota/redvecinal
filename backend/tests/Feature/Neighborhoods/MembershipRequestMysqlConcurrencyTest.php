<?php

namespace Tests\Feature\Neighborhoods;

use App\Domains\Neighborhoods\Enums\MembershipRequestStatus;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Models\NeighborhoodMembershipRequest;
use App\Domains\Neighborhoods\Policies\NeighborhoodMembershipRequestPolicy;
use App\Domains\Neighborhoods\Services\AddGroupMemberService;
use App\Domains\Neighborhoods\Services\AssignPresidentService;
use App\Domains\Neighborhoods\Services\SubmitMembershipRequestService;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\DatabaseTruncation;
use Illuminate\Process\ProcessPoolResults;
use Illuminate\Process\ProcessResult;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Process;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class MembershipRequestMysqlConcurrencyTest extends TestCase
{
    use CreatesPostFixtures, DatabaseTruncation;

    /**
     * Sin transacción por test: los workers usan otra conexión y deben ver los datos.
     *
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
            $this->markTestSkipped('Concurrencia real requiere MySQL (no SQLite en memoria).');
        }

        $this->seed(RolesAndPermissionsSeeder::class);
        $this->seedPostsBasics();
    }

    public function test_parallel_submit_creates_single_pending_request(): void
    {
        $anchor = NeighborhoodGroup::factory()->create();
        $target = NeighborhoodGroup::factory()->create(['municipality_id' => $anchor->municipality_id]);
        $vecino = User::factory()->create();
        $this->addMemberToGroup($anchor, $vecino);

        $env = $this->workerEnv($target->id, $vecino->id);
        $script = base_path('tests/Concurrency/membership_request_submit_worker.php');
        $php = PHP_BINARY;

        $command = escapeshellarg($php).' '.escapeshellarg($script);

        $results = Process::pool(function ($pool) use ($command, $env) {
            $pool->as('a')->path(base_path())->env($env)->timeout(120)->command($command);
            $pool->as('b')->path(base_path())->env($env)->timeout(120)->command($command);
        })->wait();

        $this->finalizeWorkerPool($results);

        $outputs = [$results['a']->output(), $results['b']->output()];
        $oks = collect($outputs)->filter(fn (string $o) => str_contains($o, 'OK'))->count();
        $conflicts = collect($outputs)->filter(fn (string $o) => str_contains($o, 'ERR:409'))->count();
        $pendingCount = NeighborhoodMembershipRequest::query()
            ->where('neighborhood_group_id', $target->id)
            ->where('user_id', $vecino->id)
            ->where('status', MembershipRequestStatus::Pending)
            ->count();

        $this->assertSame(1, $pendingCount, 'Outputs: '.implode(' | ', $outputs));
        $this->assertStringNotContainsString('ERR:500', implode(' ', $outputs));
        $this->assertSame(2, $oks + $conflicts, 'Outputs: '.implode(' | ', $outputs));
        $this->assertGreaterThanOrEqual(1, $conflicts, 'At least one worker must observe conflict');
    }

    public function test_parallel_submit_api_and_reject_filament_do_not_dual_pending(): void
    {
        $anchor = NeighborhoodGroup::factory()->create();
        $target = NeighborhoodGroup::factory()->create(['municipality_id' => $anchor->municipality_id]);
        $vecino = User::factory()->create();
        $this->addMemberToGroup($anchor, $vecino);
        $admin = User::factory()->create();
        $pendingMember = app(AddGroupMemberService::class)->execute($target, $vecino, $admin);

        $submitScript = base_path('tests/Concurrency/membership_request_submit_worker.php');
        $rejectScript = base_path('tests/Concurrency/reject_group_member_worker.php');
        $php = PHP_BINARY;

        $submitEnv = $this->workerEnv($target->id, $vecino->id);
        $rejectEnv = array_merge($this->workerEnv($target->id, $vecino->id), [
            'MR_GROUP_MEMBER_ID' => (string) $pendingMember->id,
            'MR_ACTOR_USER_ID' => (string) $admin->id,
        ]);

        $results = Process::pool(function ($pool) use ($php, $submitScript, $rejectScript, $submitEnv, $rejectEnv) {
            $pool->as('submit')
                ->path(base_path())
                ->env($submitEnv)
                ->timeout(120)
                ->command(escapeshellarg($php).' '.escapeshellarg($submitScript));
            $pool->as('reject')
                ->path(base_path())
                ->env($rejectEnv)
                ->timeout(120)
                ->command(escapeshellarg($php).' '.escapeshellarg($rejectScript));
        })->wait();

        $this->finalizeWorkerPool($results);

        $outputs = $results['submit']->output().' | '.$results['reject']->output();
        $this->assertStringNotContainsString('ERR:500', $outputs, $outputs);

        $memberPending = GroupMember::query()
            ->where('neighborhood_group_id', $target->id)
            ->where('user_id', $vecino->id)
            ->where('status', MembershipStatus::Pending)
            ->exists();
        $requestPending = NeighborhoodMembershipRequest::query()
            ->where('neighborhood_group_id', $target->id)
            ->where('user_id', $vecino->id)
            ->where('status', MembershipRequestStatus::Pending)
            ->exists();

        $this->assertFalse($memberPending && $requestPending, 'No deben coexistir pendientes en ambos canales: '.$outputs);
        $this->assertFalse(
            GroupMember::query()
                ->where('neighborhood_group_id', $target->id)
                ->where('user_id', $vecino->id)
                ->where('status', MembershipStatus::Active)
                ->exists()
        );
    }

    public function test_parallel_approve_and_cancel_leaves_single_terminal_state(): void
    {
        $anchor = NeighborhoodGroup::factory()->create();
        $target = NeighborhoodGroup::factory()->create(['municipality_id' => $anchor->municipality_id]);
        $vecino = User::factory()->create();
        $this->addMemberToGroup($anchor, $vecino);
        $admin = User::factory()->create();
        $president = User::factory()->create();
        app(AddGroupMemberService::class)->execute($target, $president, $admin, MembershipStatus::Active);
        app(\App\Domains\Neighborhoods\Services\AssignPresidentService::class)->execute($target, $president, $admin);

        $request = app(SubmitMembershipRequestService::class)->execute($target, $vecino, 'parallel');

        $approveScript = base_path('tests/Concurrency/membership_request_approve_worker.php');
        $cancelScript = base_path('tests/Concurrency/membership_request_cancel_worker.php');
        $php = PHP_BINARY;

        $base = $this->workerEnv($target->id, $vecino->id);
        $approveEnv = array_merge($base, [
            'MR_REQUEST_ID' => (string) $request->id,
            'MR_ACTOR_USER_ID' => (string) $president->id,
        ]);
        $cancelEnv = array_merge($base, [
            'MR_REQUEST_ID' => (string) $request->id,
            'MR_USER_ID' => (string) $vecino->id,
        ]);

        $results = Process::pool(function ($pool) use ($php, $approveScript, $cancelScript, $approveEnv, $cancelEnv) {
            $pool->as('approve')
                ->path(base_path())
                ->env($approveEnv)
                ->timeout(120)
                ->command(escapeshellarg($php).' '.escapeshellarg($approveScript));
            $pool->as('cancel')
                ->path(base_path())
                ->env($cancelEnv)
                ->timeout(120)
                ->command(escapeshellarg($php).' '.escapeshellarg($cancelScript));
        })->wait();

        $this->finalizeWorkerPool($results);

        $outputs = $results['approve']->output().' | '.$results['cancel']->output();
        $this->assertStringNotContainsString('ERR:500', $outputs, $outputs);

        $request->refresh();
        $this->assertContains($request->status, [
            MembershipRequestStatus::Approved,
            MembershipRequestStatus::Cancelled,
        ], $outputs);
        $this->assertNotSame(MembershipRequestStatus::Pending, $request->status);

        if ($request->status === MembershipRequestStatus::Approved) {
            $this->assertTrue(
                GroupMember::query()
                    ->where('neighborhood_group_id', $target->id)
                    ->where('user_id', $vecino->id)
                    ->where('status', MembershipStatus::Active)
                    ->exists()
            );
        }
    }

    public function test_parallel_approve_and_reject_resolve_single_terminal_state(): void
    {
        $this->assertTestingMysqlDatabase();

        [$target, $vecino, $request, $reviewerA, $reviewerB] = $this->pendingMembershipRequestWithTwoReviewers();

        $approveScript = base_path('tests/Concurrency/membership_request_approve_worker.php');
        $rejectScript = base_path('tests/Concurrency/membership_request_reject_worker.php');
        $php = PHP_BINARY;

        $base = $this->workerEnv($target->id, $vecino->id);
        $approveEnv = array_merge($base, [
            'MR_REQUEST_ID' => (string) $request->id,
            'MR_ACTOR_USER_ID' => (string) $reviewerA->id,
        ]);
        $rejectEnv = array_merge($base, [
            'MR_REQUEST_ID' => (string) $request->id,
            'MR_ACTOR_USER_ID' => (string) $reviewerB->id,
        ]);

        $pendingBefore = $request->fresh()->status->value;
        $this->assertFixturePending($request);

        $results = Process::pool(function ($pool) use ($php, $approveScript, $rejectScript, $approveEnv, $rejectEnv) {
            $pool->as('approve')
                ->path(base_path())
                ->env($approveEnv)
                ->timeout(120)
                ->command(escapeshellarg($php).' '.escapeshellarg($approveScript));
            $pool->as('reject')
                ->path(base_path())
                ->env($rejectEnv)
                ->timeout(120)
                ->command(escapeshellarg($php).' '.escapeshellarg($rejectScript));
        })->wait();

        $this->finalizeWorkerPool($results);

        $approveOut = $results['approve']->output();
        $rejectOut = $results['reject']->output();
        $outputs = $approveOut.' | '.$rejectOut;
        $evidence = $this->concurrencyEvidence($request, $target, $vecino, [
            'approve' => $results['approve'],
            'reject' => $results['reject'],
        ], $outputs, $pendingBefore);

        $request->refresh();
        $this->assertPersistedApproveOrRejectResolution($request, $target, $vecino, $evidence);
        $this->assertConcurrentReviewOutcomes($outputs, $evidence);
        $this->assertNoMysqlDeadlockSignals($outputs, $evidence);
    }

    public function test_parallel_approve_and_approve_create_single_active_membership(): void
    {
        $this->assertTestingMysqlDatabase();

        [$target, $vecino, $request, $reviewerA, $reviewerB] = $this->pendingMembershipRequestWithTwoReviewers();

        $approveScript = base_path('tests/Concurrency/membership_request_approve_worker.php');
        $php = PHP_BINARY;
        $base = $this->workerEnv($target->id, $vecino->id);

        $envA = array_merge($base, [
            'MR_REQUEST_ID' => (string) $request->id,
            'MR_ACTOR_USER_ID' => (string) $reviewerA->id,
        ]);
        $envB = array_merge($base, [
            'MR_REQUEST_ID' => (string) $request->id,
            'MR_ACTOR_USER_ID' => (string) $reviewerB->id,
        ]);

        $pendingBefore = $request->fresh()->status->value;
        $this->assertFixturePending($request);

        $results = Process::pool(function ($pool) use ($php, $approveScript, $envA, $envB) {
            $pool->as('a')
                ->path(base_path())
                ->env($envA)
                ->timeout(120)
                ->command(escapeshellarg($php).' '.escapeshellarg($approveScript));
            $pool->as('b')
                ->path(base_path())
                ->env($envB)
                ->timeout(120)
                ->command(escapeshellarg($php).' '.escapeshellarg($approveScript));
        })->wait();

        $this->finalizeWorkerPool($results);

        $outputs = $results['a']->output().' | '.$results['b']->output();
        $evidence = $this->concurrencyEvidence($request, $target, $vecino, [
            'a' => $results['a'],
            'b' => $results['b'],
        ], $outputs, $pendingBefore);

        $request->refresh();
        $this->assertPersistedDoubleApproveResolution($request, $target, $vecino, $evidence);
        $this->assertConcurrentReviewOutcomes($outputs, $evidence);
        $this->assertNoMysqlDeadlockSignals($outputs, $evidence);
    }

    /**
     * @return array{0: NeighborhoodGroup, 1: User, 2: NeighborhoodMembershipRequest, 3: User, 4: User}
     */
    private function pendingMembershipRequestWithTwoReviewers(): array
    {
        $anchor = NeighborhoodGroup::factory()->create();
        $target = NeighborhoodGroup::factory()->create(['municipality_id' => $anchor->municipality_id]);
        $vecino = User::factory()->create();
        $this->addMemberToGroup($anchor, $vecino);

        $admin = User::factory()->create();
        $president = User::factory()->create();
        app(AddGroupMemberService::class)->execute($target, $president, $admin, MembershipStatus::Active);
        app(AssignPresidentService::class)->execute($target, $president, $admin);

        $municipalReviewer = $this->municipalAdministratorFor($target->municipality);

        $request = app(SubmitMembershipRequestService::class)->execute($target, $vecino, 'concurrency-review');

        $policy = app(NeighborhoodMembershipRequestPolicy::class);
        $this->assertTrue($policy->approve($president, $request));
        $this->assertTrue($policy->approve($municipalReviewer, $request));
        $this->assertTrue($policy->reject($president, $request));
        $this->assertTrue($policy->reject($municipalReviewer, $request));

        return [$target, $vecino, $request, $president, $municipalReviewer];
    }

    private function assertTestingMysqlDatabase(): void
    {
        $this->assertSame('testing', config('app.env'));
        $this->assertSame('mysql', DB::connection()->getDriverName());
        $this->assertSame('red_vecinal_testing', config('database.connections.mysql.database'));
        $this->assertSame('red_vecinal_testing', DB::connection()->getDatabaseName());
    }

    private function assertFixturePending(NeighborhoodMembershipRequest $request): void
    {
        $fresh = $request->fresh();
        $this->assertNotNull($fresh);
        $this->assertSame(
            MembershipRequestStatus::Pending,
            $fresh->status,
            'request_id='.$fresh->id.' status='.$fresh->status->value
        );
    }

    /**
     * @param  array<string, ProcessResult>  $workers
     */
    private function concurrencyEvidence(
        NeighborhoodMembershipRequest $request,
        NeighborhoodGroup $target,
        User $vecino,
        array $workers,
        string $combinedStdout,
        string $pendingBefore,
    ): string {
        $workerParts = [];
        foreach ($workers as $label => $result) {
            $workerParts[] = sprintf(
                '%s[exit=%d stdout=%s stderr=%s]',
                $label,
                $result->exitCode(),
                trim($result->output()),
                trim($result->errorOutput()),
            );
        }

        $active = GroupMember::query()
            ->where('neighborhood_group_id', $target->id)
            ->where('user_id', $vecino->id)
            ->where('status', MembershipStatus::Active)
            ->count();

        $refreshed = $request->fresh();

        return sprintf(
            'request_id=%s pending_before=%s combined_stdout=%s workers=%s persisted_status=%s active_members=%d',
            (string) $request->id,
            $pendingBefore,
            trim($combinedStdout),
            implode(' ', $workerParts),
            $refreshed?->status->value ?? 'null',
            $active,
        );
    }

    private function assertConcurrentReviewOutcomes(string $outputs, string $evidence): void
    {
        $okCount = 0;
        $segments = preg_split('/\s*\|\s*/', trim($outputs)) ?: [];
        foreach ($segments as $segment) {
            foreach (preg_split('/\R/', trim($segment)) as $line) {
                if ($line === 'OK') {
                    $okCount++;
                }
            }
        }

        $conflictCount = preg_match_all('/ERR:409[: ]/', $outputs);
        $serverErrorCount = preg_match_all('/ERR:500/', $outputs);

        $this->assertSame(0, $serverErrorCount, '500 is not an acceptable concurrent outcome: '.$evidence);
        $this->assertSame(1, $okCount, 'Exactly one successful review expected: '.$evidence);
        $this->assertSame(1, $conflictCount, 'Exactly one conflict expected: '.$evidence);
        $this->assertSame(2, $okCount + $conflictCount, 'Both workers must terminate with OK or 409: '.$evidence);
    }

    private function assertPersistedApproveOrRejectResolution(
        NeighborhoodMembershipRequest $request,
        NeighborhoodGroup $target,
        User $vecino,
        string $outputs,
    ): void {
        $activeCount = GroupMember::query()
            ->where('neighborhood_group_id', $target->id)
            ->where('user_id', $vecino->id)
            ->where('status', MembershipStatus::Active)
            ->count();

        $context = 'persisted status='.$request->status->value.' active_members='.$activeCount.' outputs='.$outputs;

        $this->assertNotSame(MembershipRequestStatus::Pending, $request->status, $context);
        $this->assertContains($request->status, [
            MembershipRequestStatus::Approved,
            MembershipRequestStatus::Rejected,
        ], $context);

        if ($request->status === MembershipRequestStatus::Rejected) {
            $this->assertSame(0, $activeCount, $context);
        } else {
            $this->assertSame(1, $activeCount, $context);
        }
    }

    private function assertPersistedDoubleApproveResolution(
        NeighborhoodMembershipRequest $request,
        NeighborhoodGroup $target,
        User $vecino,
        string $outputs,
    ): void {
        $activeCount = GroupMember::query()
            ->where('neighborhood_group_id', $target->id)
            ->where('user_id', $vecino->id)
            ->where('status', MembershipStatus::Active)
            ->count();

        $context = 'persisted status='.$request->status->value.' active_members='.$activeCount.' outputs='.$outputs;

        $this->assertSame(MembershipRequestStatus::Approved, $request->status, $context);
        $this->assertSame(1, $activeCount, $context);
    }

    private function assertNoMysqlDeadlockSignals(string $outputs, string $evidence): void
    {
        $this->assertStringNotContainsString('1213', $outputs, 'MySQL deadlock detected: '.$evidence);
        $this->assertStringNotContainsString('1205', $outputs, 'MySQL lock wait timeout detected: '.$evidence);
        $this->assertStringNotContainsString('Deadlock found', $outputs, $evidence);
        $this->assertStringNotContainsString('Lock wait timeout', $outputs, $evidence);
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

    /**
     * @return array<string, string>
     */
    private function workerEnv(int $groupId, int $userId): array
    {
        $connection = config('database.default');
        $db = config("database.connections.{$connection}");

        return [
            'APP_ENV' => (string) config('app.env'),
            'APP_KEY' => (string) config('app.key'),
            'DB_CONNECTION' => (string) $connection,
            'DB_HOST' => (string) ($db['host'] ?? '127.0.0.1'),
            'DB_PORT' => (string) ($db['port'] ?? '3306'),
            'DB_DATABASE' => (string) ($db['database'] ?? ''),
            'DB_USERNAME' => (string) ($db['username'] ?? ''),
            'DB_PASSWORD' => (string) ($db['password'] ?? ''),
            'MR_GROUP_ID' => (string) $groupId,
            'MR_USER_ID' => (string) $userId,
        ];
    }
}
