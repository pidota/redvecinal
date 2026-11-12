<?php

namespace Tests\Feature\Neighborhoods;

use App\Domains\Neighborhoods\Enums\MembershipRequestStatus;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Models\NeighborhoodMembershipRequest;
use App\Domains\Neighborhoods\Services\AddGroupMemberService;
use App\Domains\Neighborhoods\Services\SubmitMembershipRequestService;
use App\Models\User;
use Database\Seeders\RolesAndPermissionsSeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Process;
use Tests\Concerns\CreatesPostFixtures;
use Tests\TestCase;

class MembershipRequestMysqlConcurrencyTest extends TestCase
{
    use CreatesPostFixtures, RefreshDatabase;

    /**
     * Sin transacción por test: los workers usan otra conexión y deben ver los datos.
     *
     * @var array<int, string>
     */
    protected array $connectionsToTransact = [];

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
            $pool->as('a')->path(base_path())->env($env)->timeout(120)->start($command);
            $pool->as('b')->path(base_path())->env($env)->timeout(120)->start($command);
        })->wait();

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
                ->start(escapeshellarg($php).' '.escapeshellarg($submitScript));
            $pool->as('reject')
                ->path(base_path())
                ->env($rejectEnv)
                ->timeout(120)
                ->start(escapeshellarg($php).' '.escapeshellarg($rejectScript));
        })->wait();

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
                ->start(escapeshellarg($php).' '.escapeshellarg($approveScript));
            $pool->as('cancel')
                ->path(base_path())
                ->env($cancelEnv)
                ->timeout(120)
                ->start(escapeshellarg($php).' '.escapeshellarg($cancelScript));
        })->wait();

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
