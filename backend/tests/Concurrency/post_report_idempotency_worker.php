<?php

use App\Domains\Posts\Exceptions\PostReportIdempotencyException;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Services\ReportPostService;
use App\Models\User;
use Illuminate\Contracts\Console\Kernel;
use Illuminate\Database\DeadlockException;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;
use Tests\Concurrency\PostReportIdempotencyBarrier;

$basePath = dirname(__DIR__, 2);

$requiredEnv = ['DB_CONNECTION', 'DB_DATABASE', 'APP_KEY', 'PR_POST_ID', 'PR_USER_ID', 'PR_IDEMPOTENCY_KEY', 'PR_BARRIER_DIR', 'PR_WORKER_SLOT'];
foreach ($requiredEnv as $key) {
    if (getenv($key) === false) {
        fwrite(STDOUT, "ERR:2:missing env {$key}\n");
        exit(0);
    }
}

require $basePath.'/vendor/autoload.php';

$app = require $basePath.'/bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

if ((string) config('app.env') !== 'testing') {
    fwrite(STDOUT, "ERR:2:app_env\n");
    exit(0);
}

$default = (string) config('database.default');
$dbName = (string) config("database.connections.{$default}.database");
if ($dbName !== 'red_vecinal_testing') {
    fwrite(STDOUT, "ERR:2:database\n");
    exit(0);
}

if ($default !== 'mysql' || DB::connection()->getDriverName() !== 'mysql') {
    fwrite(STDOUT, "ERR:2:driver\n");
    exit(0);
}

$version = (string) (DB::selectOne('select version() as v')->v ?? '');
if (! str_starts_with($version, '8.4.')) {
    fwrite(STDOUT, "ERR:2:mysql_version\n");
    exit(0);
}

$postId = (int) (getenv('PR_POST_ID') ?: 0);
$userId = (int) (getenv('PR_USER_ID') ?: 0);
$key = (string) getenv('PR_IDEMPOTENCY_KEY');
$reason = (string) (getenv('PR_REASON_CODE') ?: 'spam');
$detailsEnv = getenv('PR_DETAILS');
$details = $detailsEnv === false ? null : (string) $detailsEnv;
$barrierDir = (string) getenv('PR_BARRIER_DIR');
$slot = (string) getenv('PR_WORKER_SLOT');
$timeoutMs = (int) (getenv('PR_BARRIER_TIMEOUT_MS') ?: PostReportIdempotencyBarrier::DEFAULT_TIMEOUT_MS);

if ($postId === 0 || $userId === 0 || $key === '' || ($slot !== 'a' && $slot !== 'b')) {
    fwrite(STDOUT, "ERR:2:args\n");
    exit(0);
}

$post = Post::query()->find($postId);
$user = User::query()->find($userId);

if ($post === null || $user === null) {
    fwrite(STDOUT, "ERR:2:fixture not found\n");
    exit(0);
}

try {
    PostReportIdempotencyBarrier::announceReady($barrierDir, $slot);
    PostReportIdempotencyBarrier::waitForGo($barrierDir, $timeoutMs);
} catch (Throwable $e) {
    fwrite(STDOUT, "ERR:2:barrier\n");
    exit(0);
}

try {
    $report = app(ReportPostService::class)->execute($user, $reason, $post, null, $details, $key);
    fwrite(STDOUT, 'OK:'.$report->id."\n");
    exit(0);
} catch (PostReportIdempotencyException $e) {
    fwrite(STDOUT, 'ERR:'.$e->httpStatus."\n");
    exit(0);
} catch (DeadlockException $e) {
    fwrite(STDOUT, "ERR:1213\n");
    exit(0);
} catch (QueryException $e) {
    $driverCode = $e->errorInfo[1] ?? null;
    if ($driverCode === 1213) {
        fwrite(STDOUT, "ERR:1213\n");
        exit(0);
    }
    if ($driverCode === 1205) {
        fwrite(STDOUT, "ERR:1205\n");
        exit(0);
    }
    fwrite(STDOUT, "ERR:500\n");
    exit(0);
} catch (Throwable $e) {
    fwrite(STDOUT, "ERR:500\n");
    exit(0);
}
