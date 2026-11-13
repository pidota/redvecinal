<?php

/**
 * Crea o verifica la base MySQL dedicada a pruebas. No ejecutar si APP_ENV=production.
 * No escribe credenciales en salida.
 *
 * Uso: php scripts/test/ensure_mysql_testing_database.php
 */

declare(strict_types=1);

use Illuminate\Contracts\Console\Kernel;

const TESTING_DATABASE = 'red_vecinal_testing';

$basePath = dirname(__DIR__, 2);
require $basePath.'/vendor/autoload.php';
$app = require $basePath.'/bootstrap/app.php';
$app->make(Kernel::class)->bootstrap();

if (app()->environment('production')) {
    fwrite(STDERR, "Abortado: entorno production.\n");
    exit(1);
}

$connection = config('database.connections.mysql');
$devDatabase = (string) ($connection['database'] ?? '');
$host = (string) ($connection['host'] ?? '127.0.0.1');
$port = (string) ($connection['port'] ?? '3306');
$user = (string) ($connection['username'] ?? 'root');
$password = (string) ($connection['password'] ?? '');

if ($devDatabase === '') {
    fwrite(STDERR, "Abortado: no se pudo resolver DB_DATABASE del entorno local.\n");
    exit(1);
}

if ($devDatabase === TESTING_DATABASE) {
    fwrite(STDERR, "Abortado: la base de desarrollo no debe ser ".TESTING_DATABASE.".\n");
    exit(1);
}

$unsafeNames = ['production', 'prod', 'red_vecinal_prod'];
foreach ($unsafeNames as $unsafe) {
    if (strcasecmp($devDatabase, $unsafe) === 0) {
        fwrite(STDERR, "Abortado: nombre de base de desarrollo no permitido para esta operación.\n");
        exit(1);
    }
}

try {
    $dsn = "mysql:host={$host};port={$port};charset=utf8mb4";
    $pdo = new PDO($dsn, $user, $password, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
    ]);
    $pdo->exec(
        'CREATE DATABASE IF NOT EXISTS `'.TESTING_DATABASE.'` '
        .'CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci'
    );
    $version = $pdo->query('SELECT VERSION()')->fetchColumn();
} catch (Throwable $e) {
    fwrite(STDERR, 'Abortado: no se pudo conectar o crear la base de testing: '.$e->getMessage()."\n");
    exit(1);
}

$pdo->exec('USE `'.TESTING_DATABASE.'`');
$active = $pdo->query('SELECT DATABASE()')->fetchColumn();
if ($active !== TESTING_DATABASE) {
    fwrite(STDERR, "Abortado: DATABASE() activa inesperada.\n");
    exit(1);
}

echo "ensure_mysql_testing_database: ok\n";
echo "mysql_version={$version}\n";
echo "host={$host}\n";
echo "port={$port}\n";
echo "dev_database={$devDatabase}\n";
echo "test_database=".TESTING_DATABASE."\n";
