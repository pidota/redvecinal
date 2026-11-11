<?php

/**
 * Genera fixture JSON para validación E2E Reverb (solo desarrollo local).
 * Inserta datos ficticios en la BD local configurada en .env — no usar en producción.
 *
 * Uso: php prepare-fixture.php fixture.json
 */

use App\Domains\Chat\Services\EnsureGroupChatRoomService;
use App\Domains\Municipality\Models\Municipality;
use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Enums\NeighborhoodGroupStatus;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Models\User;
use Illuminate\Support\Str;

require __DIR__.'/../../../vendor/autoload.php';
$app = require __DIR__.'/../../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

$municipalityA = Municipality::query()->firstOrCreate(
    ['slug' => 'chepica'],
    [
        'name' => 'Municipalidad de Chépica',
        'region_code' => '06',
        'commune_code' => '06302',
        'status' => 'active',
        'settings' => ['country' => 'CL', 'display_name' => 'Chépica'],
    ],
);

$municipalityB = Municipality::query()->firstOrCreate(
    ['slug' => 'reverb-e2e-muni-b'],
    [
        'name' => 'Municipio ficticio E2E Reverb',
        'region_code' => '99',
        'commune_code' => '99999',
        'status' => 'active',
        'settings' => ['display_name' => 'E2E Municipio B'],
    ],
);

$juntaA = NeighborhoodGroup::factory()->create([
    'municipality_id' => $municipalityA->id,
    'name' => 'Junta E2E Reverb A',
    'slug' => 'junta-e2e-reverb-a-'.Str::lower(Str::random(6)),
    'status' => NeighborhoodGroupStatus::Active,
]);

$juntaB = NeighborhoodGroup::factory()->create([
    'municipality_id' => $municipalityA->id,
    'name' => 'Junta E2E Reverb B',
    'slug' => 'junta-e2e-reverb-b-'.Str::lower(Str::random(6)),
    'status' => NeighborhoodGroupStatus::Active,
]);

$juntaC = NeighborhoodGroup::factory()->create([
    'municipality_id' => $municipalityB->id,
    'name' => 'Junta E2E Reverb C',
    'slug' => 'junta-e2e-reverb-c-'.Str::lower(Str::random(6)),
    'status' => NeighborhoodGroupStatus::Active,
]);

$juntaSuspended = NeighborhoodGroup::factory()->suspended()->create([
    'municipality_id' => $municipalityA->id,
    'name' => 'Junta E2E Reverb Suspendida',
    'slug' => 'junta-e2e-reverb-susp-'.Str::lower(Str::random(6)),
]);

$suffix = Str::lower(Str::random(8));
$userA1 = User::factory()->create(['email' => "reverb-e2e-a1-{$suffix}@example.test", 'name' => 'E2E A1']);
$userA2 = User::factory()->create(['email' => "reverb-e2e-a2-{$suffix}@example.test", 'name' => 'E2E A2']);
$userA3 = User::factory()->create(['email' => "reverb-e2e-a3-{$suffix}@example.test", 'name' => 'E2E A3 Suspendido']);
$userB1 = User::factory()->create(['email' => "reverb-e2e-b1-{$suffix}@example.test", 'name' => 'E2E B1']);
$userC1 = User::factory()->create(['email' => "reverb-e2e-c1-{$suffix}@example.test", 'name' => 'E2E C1']);

$memberships = [
    [$userA1, $juntaA, MembershipStatus::Active],
    [$userA2, $juntaA, MembershipStatus::Active],
    [$userA3, $juntaA, MembershipStatus::Suspended],
    [$userB1, $juntaB, MembershipStatus::Active],
    [$userC1, $juntaC, MembershipStatus::Active],
    [$userA2, $juntaSuspended, MembershipStatus::Active],
];

foreach ($memberships as [$user, $group, $status]) {
    GroupMember::factory()->create([
        'neighborhood_group_id' => $group->id,
        'municipality_id' => $group->municipality_id,
        'user_id' => $user->id,
        'membership_role' => MembershipRole::Member,
        'status' => $status,
    ]);
}

$ensureRoom = app(EnsureGroupChatRoomService::class);
$roomA = $ensureRoom->execute($juntaA);
$roomSuspended = $ensureRoom->execute($juntaSuspended);

$fixture = [
    'appUrl' => rtrim((string) config('app.url'), '/'),
    'roomId' => $roomA->id,
    'roomSuspendedId' => $roomSuspended->id,
    'juntaSuspendedId' => $juntaSuspended->id,
    'reverbKey' => (string) config('broadcasting.connections.reverb.key', env('REVERB_APP_KEY')),
    'reverbHost' => (string) env('REVERB_HOST', 'localhost'),
    'reverbPort' => (int) env('REVERB_PORT', 8080),
    'reverbScheme' => (string) env('REVERB_SCHEME', 'http'),
    'a1Token' => $userA1->createToken('reverb-e2e-a1')->plainTextToken,
    'a2Token' => $userA2->createToken('reverb-e2e-a2')->plainTextToken,
    'a3SuspendedToken' => $userA3->createToken('reverb-e2e-a3')->plainTextToken,
    'b1Token' => $userB1->createToken('reverb-e2e-b1')->plainTextToken,
    'c1Token' => $userC1->createToken('reverb-e2e-c1')->plainTextToken,
    'a2UserId' => $userA2->id,
    'juntaAId' => $juntaA->id,
    // Compatibilidad con run.mjs original
    'senderToken' => null,
    'receiverToken' => null,
    'intruderToken' => null,
];

$fixture['senderToken'] = $fixture['a1Token'];
$fixture['receiverToken'] = $fixture['a2Token'];
$fixture['intruderToken'] = $fixture['b1Token'];

$json = json_encode($fixture, JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES);
$out = $argv[1] ?? null;
if ($out) {
    file_put_contents($out, $json);

    exit(0);
}

echo $json;
