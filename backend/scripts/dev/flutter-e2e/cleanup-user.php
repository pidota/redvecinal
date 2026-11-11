<?php

/**
 * Elimina usuario creado por prepare-user.php (solo desarrollo local).
 *
 * Uso: php cleanup-user.php [email]
 */

use App\Models\User;
use Laravel\Sanctum\PersonalAccessToken;

require __DIR__.'/../../../vendor/autoload.php';
$app = require __DIR__.'/../../../bootstrap/app.php';
$app->make(Illuminate\Contracts\Console\Kernel::class)->bootstrap();

if (app()->environment('production')) {
    fwrite(STDERR, "Abortado: entorno production.\n");
    exit(1);
}

$credentialsPath = dirname(__DIR__, 4).'/mobile/scripts/.flutter-e2e-credentials.json';
$email = $argv[1] ?? null;

if ($email === null && is_file($credentialsPath)) {
    $payload = json_decode((string) file_get_contents($credentialsPath), true);
    $email = $payload['email'] ?? null;
}

if (! is_string($email) || $email === '') {
    fwrite(STDERR, "Indique email o ejecute prepare-user.php antes.\n");
    exit(1);
}

if (! preg_match('/^flutter-e2e-[a-z0-9]{8}@red-vecinal\.test$/', $email)) {
    fwrite(STDERR, "Solo se eliminan usuarios creados por prepare-user.php (flutter-e2e-*@red-vecinal.test).\n");
    exit(1);
}

if (! in_array(app()->environment(), ['local', 'testing', 'development'], true)) {
    fwrite(STDERR, "Abortado: entorno no permitido para cleanup de fixture.\n");
    exit(1);
}

$user = User::query()->where('email', $email)->first();
if ($user === null) {
    echo "Usuario no encontrado: {$email}\n";
    exit(0);
}

PersonalAccessToken::query()->where('tokenable_id', $user->id)->where('tokenable_type', $user::class)->delete();
$user->delete();

if (is_file($credentialsPath)) {
    unlink($credentialsPath);
}

echo "Eliminado usuario {$email}\n";
