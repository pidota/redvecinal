<?php

use App\Domains\Neighborhoods\Exceptions\MembershipRequestException;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Domains\Neighborhoods\Services\SubmitMembershipRequestService;
use App\Models\User;
use Illuminate\Contracts\Console\Kernel;
use Illuminate\Database\QueryException;

$basePath = dirname(__DIR__, 2);

$requiredEnv = ['DB_CONNECTION', 'DB_DATABASE', 'APP_KEY', 'MR_GROUP_ID', 'MR_USER_ID'];
foreach ($requiredEnv as $key) {
    if (getenv($key) === false) {
        fwrite(STDOUT, "ERR:2:missing env {$key}\n");
        exit(0);
    }
}

require $basePath.'/vendor/autoload.php';

$app = require $basePath.'/bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

$groupId = (int) (getenv('MR_GROUP_ID') ?: 0);
$userId = (int) (getenv('MR_USER_ID') ?: 0);

if ($groupId === 0 || $userId === 0) {
    fwrite(STDERR, "missing MR_GROUP_ID or MR_USER_ID\n");
    exit(2);
}

$group = NeighborhoodGroup::query()->find($groupId);
$user = User::query()->find($userId);

if ($group === null || $user === null) {
    $db = (string) config('database.connections.'.config('database.default').'.database');
    fwrite(STDOUT, "ERR:2:fixture not found db={$db} group={$groupId} user={$userId}\n");
    exit(0);
}

try {
    app(SubmitMembershipRequestService::class)->execute($group, $user, 'worker');
    fwrite(STDOUT, "OK\n");
    exit(0);
} catch (MembershipRequestException $e) {
    fwrite(STDOUT, 'ERR:'.$e->httpStatus.':'.$e->getMessage()."\n");
    exit(0);
} catch (QueryException $e) {
    fwrite(STDOUT, 'ERR:500:query:'.$e->getMessage()."\n");
    exit(0);
}
