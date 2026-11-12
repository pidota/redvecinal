<?php

use App\Domains\Neighborhoods\Exceptions\MembershipRequestException;
use App\Domains\Neighborhoods\Models\NeighborhoodMembershipRequest;
use App\Domains\Neighborhoods\Services\CancelMembershipRequestService;
use App\Models\User;
use Illuminate\Contracts\Console\Kernel;
use Illuminate\Database\QueryException;

$basePath = dirname(__DIR__, 2);

foreach (['DB_CONNECTION', 'DB_DATABASE', 'APP_KEY', 'MR_REQUEST_ID', 'MR_USER_ID'] as $key) {
    if (getenv($key) === false) {
        fwrite(STDOUT, "ERR:2:missing env {$key}\n");
        exit(0);
    }
}

require $basePath.'/vendor/autoload.php';

$app = require $basePath.'/bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

$requestId = (int) getenv('MR_REQUEST_ID');
$userId = (int) getenv('MR_USER_ID');

$request = NeighborhoodMembershipRequest::query()->find($requestId);
$user = User::query()->find($userId);

if ($request === null || $user === null) {
    fwrite(STDOUT, "ERR:2:fixture not found\n");
    exit(0);
}

try {
    app(CancelMembershipRequestService::class)->execute($request, $user);
    fwrite(STDOUT, "OK\n");
    exit(0);
} catch (MembershipRequestException $e) {
    fwrite(STDOUT, 'ERR:'.$e->httpStatus.':'.$e->getMessage()."\n");
    exit(0);
} catch (QueryException $e) {
    fwrite(STDOUT, 'ERR:500:query:'.$e->getMessage()."\n");
    exit(0);
}
