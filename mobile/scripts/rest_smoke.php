<?php

/**
 * Smoke REST Fase 5.2B — sin imprimir contraseña ni token completo.
 */

$credentialsPath = __DIR__.'/.flutter-e2e-credentials.json';
if (! is_file($credentialsPath)) {
    fwrite(STDERR, "Falta fixture: ejecute backend/scripts/dev/flutter-e2e/prepare-user.php\n");
    exit(1);
}

$creds = json_decode((string) file_get_contents($credentialsPath), true, 512, JSON_THROW_ON_ERROR);
$base = getenv('API_BASE_URL') ?: 'http://red-vecinal.test/api/v1';

if (! is_string($creds['email'] ?? null) || ! preg_match('/^flutter-e2e-[a-z0-9]{8}@red-vecinal\.test$/', $creds['email'])) {
    fwrite(STDERR, "Credenciales no pertenecen al fixture flutter-e2e; ejecute prepare-user.php.\n");
    exit(1);
}

$host = parse_url($base, PHP_URL_HOST);
$allowedHosts = ['localhost', '127.0.0.1', '10.0.2.2', 'red-vecinal.test'];
if (! is_string($host) || (! in_array($host, $allowedHosts, true) && ! str_ends_with($host, '.test'))) {
    fwrite(STDERR, "API_BASE_URL no permitida para smoke local: {$base}\n");
    exit(1);
}

function request(string $method, string $url, ?string $token = null, ?array $json = null): array
{
    $ch = curl_init($url);
    $headers = ['Accept: application/json'];
    if ($token !== null) {
        $headers[] = 'Authorization: Bearer '.$token;
    }
    if ($json !== null) {
        $headers[] = 'Content-Type: application/json';
        curl_setopt($ch, CURLOPT_POSTFIELDS, json_encode($json, JSON_THROW_ON_ERROR));
    }
    curl_setopt_array($ch, [
        CURLOPT_CUSTOMREQUEST => $method,
        CURLOPT_HTTPHEADER => $headers,
        CURLOPT_RETURNTRANSFER => true,
    ]);
    $body = curl_exec($ch);
    $code = (int) curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);

    return ['code' => $code, 'body' => is_string($body) ? $body : ''];
}

$login = request('POST', "$base/auth/login", null, [
    'email' => $creds['email'],
    'password' => $creds['password'],
    'device_name' => 'php-smoke',
]);
$data = json_decode($login['body'], true);
$token = is_array($data) ? ($data['token'] ?? '') : '';

$checks = [
    ['POST login', $login['code'] === 200 && $token !== '', 'http='.$login['code']],
];

$me = request('GET', "$base/me", $token);
$meJson = json_decode($me['body'], true);
$membershipCount = is_array($meJson) && is_array($meJson['municipality_memberships'] ?? null)
    ? count($meJson['municipality_memberships'])
    : -1;
$checks[] = ['GET /me', $me['code'] === 200, "http={$me['code']} memberships=$membershipCount"];

$myGroups = request('GET', "$base/me/groups", $token);
$groupsJson = json_decode($myGroups['body'], true);
$groupsData = is_array($groupsJson['data'] ?? null) ? $groupsJson['data'] : [];
$myGroupsOk = $myGroups['code'] === 200
    && is_array($groupsJson['data'] ?? null)
    && count($groupsData) >= 1;

if ($myGroupsOk) {
    $first = $groupsData[0];
    $requiredKeys = ['id', 'name', 'municipality_id', 'status'];
    foreach ($requiredKeys as $key) {
        if (! array_key_exists($key, $first)) {
            $myGroupsOk = false;
            break;
        }
    }
    if ($myGroupsOk && (! is_array($first['municipality'] ?? null)
        || ! isset($first['municipality']['id'], $first['municipality']['name'], $first['municipality']['slug']))) {
        $myGroupsOk = false;
    }
    $sensitive = ['contact_email', 'contact_phone', 'registration_number', 'settings'];
    foreach ($sensitive as $field) {
        if (array_key_exists($field, $first) || str_contains($myGroups['body'], "\"$field\"")) {
            $myGroupsOk = false;
            break;
        }
    }
}

$checks[] = [
    'GET /me/groups',
    $myGroupsOk,
    'http='.$myGroups['code'].' count='.count($groupsData),
];

$logout = request('POST', "$base/auth/logout", $token);
$checks[] = ['POST logout', in_array($logout['code'], [200, 204], true), "http={$logout['code']}"];

$meRevoked = request('GET', "$base/me", $token);
$checks[] = ['GET /me revocado', $meRevoked['code'] === 401, "http={$meRevoked['code']}"];

$badLogin = request('POST', "$base/auth/login", null, [
    'email' => $creds['email'],
    'password' => 'wrong-password',
    'device_name' => 'php-smoke',
]);
$checks[] = ['login credenciales incorrectas', $badLogin['code'] === 401, "http={$badLogin['code']}"];

$unknownLogin = request('POST', "$base/auth/login", null, [
    'email' => 'nobody-e2e@red-vecinal.test',
    'password' => 'x',
    'device_name' => 'php-smoke',
]);
$checks[] = ['login usuario desconocido', $unknownLogin['code'] === 401, "http={$unknownLogin['code']}"];

foreach ($checks as [$name, $ok, $detail]) {
    printf("%-32s %s %s\n", $name, $ok ? 'OK' : 'FAIL', $detail);
}

exit(array_reduce($checks, fn ($f, $c) => $f || ! $c[1], false) ? 1 : 0);
