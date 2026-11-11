<?php

/**
 * Genera fixture JSON para run.mjs (solo desarrollo local).
 * Uso: php prepare-fixture.php > fixture.json
 */

use App\Domains\Chat\Services\EnsureGroupChatRoomService;
use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Models\User;

require __DIR__.'/../../../vendor/autoload.php';
$app = require __DIR__.'/../../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$groupA = NeighborhoodGroup::factory()->create();
$sender = User::factory()->create();
$receiver = User::factory()->create();

foreach ([[$sender, $groupA], [$receiver, $groupA]] as [$user, $group]) {
    GroupMember::factory()->create([
        'neighborhood_group_id' => $group->id,
        'municipality_id' => $group->municipality_id,
        'user_id' => $user->id,
        'membership_role' => MembershipRole::Member,
        'status' => MembershipStatus::Active,
    ]);
}

$groupB = NeighborhoodGroup::factory()->create();
$intruder = User::factory()->create();
GroupMember::factory()->create([
    'neighborhood_group_id' => $groupB->id,
    'municipality_id' => $groupB->municipality_id,
    'user_id' => $intruder->id,
    'membership_role' => MembershipRole::Member,
    'status' => MembershipStatus::Active,
]);

$room = app(EnsureGroupChatRoomService::class)->execute($groupA);

$fixture = [
    'appUrl' => rtrim((string) config('app.url'), '/'),
    'roomId' => $room->id,
    'reverbKey' => (string) config('broadcasting.connections.reverb.key', env('REVERB_APP_KEY')),
    'reverbHost' => (string) env('REVERB_HOST', 'localhost'),
    'reverbPort' => (int) env('REVERB_PORT', 8080),
    'reverbScheme' => (string) env('REVERB_SCHEME', 'http'),
    'receiverToken' => $receiver->createToken('reverb-e2e-receiver')->plainTextToken,
    'senderToken' => $sender->createToken('reverb-e2e-sender')->plainTextToken,
    'intruderToken' => $intruder->createToken('reverb-e2e-intruder')->plainTextToken,
];

$json = json_encode($fixture, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
$out = $argv[1] ?? null;
if ($out) {
    file_put_contents($out, $json);

    exit(0);
}

echo $json;
