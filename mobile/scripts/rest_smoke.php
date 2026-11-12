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

$fixtureGroupId = $myGroupsOk ? (int) ($groupsData[0]['id'] ?? 0) : 0;

$indexGroups = request('GET', "$base/groups?page=1", $token);
$indexJson = json_decode($indexGroups['body'], true);
$indexData = is_array($indexJson['data'] ?? null) ? $indexJson['data'] : [];
$indexIds = array_map(static fn ($row) => (int) ($row['id'] ?? 0), $indexData);
$indexOk = $indexGroups['code'] === 200
    && is_array($indexJson['data'] ?? null)
    && ($fixtureGroupId === 0 || in_array($fixtureGroupId, $indexIds, true));
if ($indexOk && $fixtureGroupId > 0) {
    $first = null;
    foreach ($indexData as $row) {
        if ((int) ($row['id'] ?? 0) === $fixtureGroupId) {
            $first = $row;
            break;
        }
    }
    $indexOk = is_array($first) && isset($first['municipality']['slug']);
    foreach (['contact_email', 'contact_phone'] as $field) {
        if (str_contains($indexGroups['body'], "\"$field\"")) {
            $indexOk = false;
        }
    }
}
$meta = is_array($indexJson['meta'] ?? null) ? $indexJson['meta'] : [];
$lastPage = (int) ($meta['last_page'] ?? 1);
$currentPage = (int) ($meta['current_page'] ?? 0);
if ($indexOk) {
    $indexOk = $currentPage === 1 && $lastPage >= 1;
}
$page2Detail = 'skipped last_page=1';
$page2Ok = true;
if ($indexOk && $lastPage >= 2) {
    $indexGroups2 = request('GET', "$base/groups?page=2", $token);
    $indexJson2 = json_decode($indexGroups2['body'], true);
    $indexData2 = is_array($indexJson2['data'] ?? null) ? $indexJson2['data'] : [];
    $meta2 = is_array($indexJson2['meta'] ?? null) ? $indexJson2['meta'] : [];
    $page2Ok = $indexGroups2['code'] === 200
        && (int) ($meta2['current_page'] ?? 0) === 2
        && is_array($indexJson2['data'] ?? null);
    $page2Detail = 'http='.$indexGroups2['code'].' count='.count($indexData2).' last_page='.$lastPage;
} elseif ($indexOk) {
    $page2Detail = 'limitation fixture single page (last_page='.$lastPage.')';
}
$checks[] = ['GET /groups', $indexOk, 'http='.$indexGroups['code'].' count='.count($indexData).' meta='.$currentPage.'/'.$lastPage];
$checks[] = ['GET /groups page 2', $page2Ok, $page2Detail];

$showOk = false;
$showDetail = 'skip';
if ($fixtureGroupId > 0) {
    $show = request('GET', "$base/groups/$fixtureGroupId", $token);
    $showJson = json_decode($show['body'], true);
    $showData = is_array($showJson['data'] ?? null) ? $showJson['data'] : null;
    $showOk = $show['code'] === 200
        && is_array($showData)
        && (int) ($showData['id'] ?? 0) === $fixtureGroupId
        && isset($showData['municipality']['name']);
    foreach (['contact_email', 'contact_phone'] as $field) {
        if (str_contains($show['body'], "\"$field\"")) {
            $showOk = false;
        }
    }
    $showDetail = 'http='.$show['code'];
}
$checks[] = ['GET /groups/{id}', $showOk, $showDetail];

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
