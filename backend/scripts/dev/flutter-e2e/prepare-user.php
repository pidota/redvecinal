<?php

/**
 * Usuario local efímero para validación Flutter ↔ Laravel (solo desarrollo).
 * No usar en producción. Limpiar: php cleanup-user.php <email>
 *
 * Uso: php prepare-user.php
 */

use App\Domains\Municipality\Models\Municipality;
use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Enums\NeighborhoodGroupStatus;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Models\User;
use Illuminate\Support\Facades\Hash;
use Illuminate\Support\Str;

require __DIR__.'/../../../vendor/autoload.php';
$app = require __DIR__.'/../../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

if (app()->environment('production')) {
    fwrite(STDERR, "Abortado: entorno production.\n");
    exit(1);
}

if (! in_array(app()->environment(), ['local', 'testing', 'development'], true)) {
    fwrite(STDERR, "Abortado: ejecute solo en entorno local o de prueba.\n");
    exit(1);
}

$appUrl = (string) config('app.url');
if ($appUrl !== '' && ! preg_match('#^https?://(localhost|127\.0\.0\.1|.*\.test)(:\d+)?#i', $appUrl)) {
    fwrite(STDERR, "Abortado: APP_URL no parece un host local ({$appUrl}).\n");
    exit(1);
}

$suffix = Str::lower(Str::random(8));
$email = "flutter-e2e-{$suffix}@red-vecinal.test";
$password = 'e2e-'.bin2hex(random_bytes(12));

$municipality = Municipality::query()->firstOrCreate(
    ['slug' => 'chepica'],
    [
        'name' => 'Municipalidad de Chépica',
        'region_code' => '06',
        'commune_code' => '06302',
        'status' => 'active',
        'settings' => ['country' => 'CL', 'display_name' => 'Chépica'],
    ],
);

$group = NeighborhoodGroup::factory()->create([
    'municipality_id' => $municipality->id,
    'name' => 'Junta E2E Flutter',
    'slug' => 'junta-e2e-flutter-'.$suffix,
    'status' => NeighborhoodGroupStatus::Active,
]);

$user = User::factory()->create([
    'name' => 'Vecino E2E Flutter',
    'email' => $email,
    'password' => Hash::make($password),
]);

GroupMember::factory()->create([
    'municipality_id' => $municipality->id,
    'neighborhood_group_id' => $group->id,
    'user_id' => $user->id,
    'membership_role' => MembershipRole::Member,
    'status' => MembershipStatus::Active,
]);

$credentialsPath = dirname(__DIR__, 4).'/mobile/scripts/.flutter-e2e-credentials.json';
file_put_contents($credentialsPath, json_encode([
    'email' => $email,
    'password' => $password,
    'user_id' => $user->id,
    'created_at' => now()->toIso8601String(),
], JSON_PRETTY_PRINT));

echo json_encode(['email' => $email, 'credentials_file' => $credentialsPath], JSON_THROW_ON_ERROR).PHP_EOL;
