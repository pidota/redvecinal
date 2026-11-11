<?php

/**
 * Suspende la membresía activa de un usuario en una junta (solo fixtures E2E).
 * Uso: php suspend-member.php <user_id> <neighborhood_group_id>
 */

use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\GroupMember;

require __DIR__.'/../../../vendor/autoload.php';
$app = require __DIR__.'/../../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$userId = (int) ($argv[1] ?? 0);
$groupId = (int) ($argv[2] ?? 0);
if ($userId < 1 || $groupId < 1) {
    fwrite(STDERR, "Uso: php suspend-member.php <user_id> <neighborhood_group_id>\n");
    exit(2);
}

$updated = GroupMember::query()
    ->where('user_id', $userId)
    ->where('neighborhood_group_id', $groupId)
    ->where('status', MembershipStatus::Active)
    ->update(['status' => MembershipStatus::Suspended]);

echo json_encode(['updated' => $updated], JSON_UNESCAPED_SLASHES);
