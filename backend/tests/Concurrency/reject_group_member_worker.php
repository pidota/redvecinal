<?php

use App\Domains\Neighborhoods\Exceptions\NeighborhoodDomainException;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Services\RejectGroupMemberService;
use App\Models\User;
use Illuminate\Contracts\Console\Kernel;
use Illuminate\Database\QueryException;

$basePath = dirname(__DIR__, 2);

foreach (['DB_CONNECTION', 'DB_DATABASE', 'APP_KEY', 'MR_GROUP_MEMBER_ID', 'MR_ACTOR_USER_ID'] as $key) {
    if (getenv($key) === false) {
        fwrite(STDOUT, "ERR:2:missing env {$key}\n");
        exit(0);
    }
}

require $basePath.'/vendor/autoload.php';

$app = require $basePath.'/bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

$memberId = (int) getenv('MR_GROUP_MEMBER_ID');
$actorId = (int) getenv('MR_ACTOR_USER_ID');

$member = GroupMember::query()->find($memberId);
$actor = User::query()->find($actorId);

if ($member === null || $actor === null) {
    fwrite(STDOUT, "ERR:2:fixture not found\n");
    exit(0);
}

try {
    app(RejectGroupMemberService::class)->execute($member, $actor);
    fwrite(STDOUT, "OK\n");
    exit(0);
} catch (NeighborhoodDomainException $e) {
    fwrite(STDOUT, 'ERR:422:'.$e->getMessage()."\n");
    exit(0);
} catch (QueryException $e) {
    fwrite(STDOUT, 'ERR:500:query:'.$e->getMessage()."\n");
    exit(0);
}
