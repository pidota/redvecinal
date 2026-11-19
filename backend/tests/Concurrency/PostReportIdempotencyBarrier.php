<?php

namespace Tests\Concurrency;

use RuntimeException;

/**
 * Barrera de archivos entre el coordinador PHPUnit y dos workers.
 * No usa GET_LOCK de MySQL: no serializa el INSERT que se quiere medir.
 */
final class PostReportIdempotencyBarrier
{
    public const DEFAULT_TIMEOUT_MS = 20000;

    public static function createDirectory(): string
    {
        $dir = sys_get_temp_dir().DIRECTORY_SEPARATOR.'pr_idem_'.bin2hex(random_bytes(8));
        if (! mkdir($dir, 0700) && ! is_dir($dir)) {
            throw new RuntimeException('No se pudo crear el directorio de barrera.');
        }

        return $dir;
    }

    public static function announceReady(string $dir, string $slot): void
    {
        self::assertSafeDir($dir);
        $path = $dir.DIRECTORY_SEPARATOR.'ready_'.$slot;
        if (file_put_contents($path, '1') === false) {
            throw new RuntimeException('No se pudo marcar listo el worker.');
        }
    }

    /**
     * @param  list<string>  $slots
     */
    public static function waitUntilReady(string $dir, array $slots, int $timeoutMs = self::DEFAULT_TIMEOUT_MS): void
    {
        self::assertSafeDir($dir);
        $deadline = microtime(true) + ($timeoutMs / 1000);
        foreach ($slots as $slot) {
            $path = $dir.DIRECTORY_SEPARATOR.'ready_'.$slot;
            while (! is_file($path)) {
                if (microtime(true) > $deadline) {
                    throw new RuntimeException('Timeout esperando ready_'.$slot);
                }
                usleep(5000);
            }
        }
    }

    public static function release(string $dir): void
    {
        self::assertSafeDir($dir);
        $path = $dir.DIRECTORY_SEPARATOR.'go';
        if (file_put_contents($path, '1') === false) {
            throw new RuntimeException('No se pudo liberar la barrera.');
        }
    }

    public static function waitForGo(string $dir, int $timeoutMs = self::DEFAULT_TIMEOUT_MS): void
    {
        self::assertSafeDir($dir);
        $path = $dir.DIRECTORY_SEPARATOR.'go';
        $deadline = microtime(true) + ($timeoutMs / 1000);
        while (! is_file($path)) {
            if (microtime(true) > $deadline) {
                throw new RuntimeException('Timeout esperando go');
            }
            usleep(5000);
        }
    }

    public static function cleanup(string $dir): void
    {
        if (! is_dir($dir) || ! str_contains($dir, 'pr_idem_')) {
            return;
        }
        foreach ((array) scandir($dir) as $name) {
            if ($name === '.' || $name === '..') {
                continue;
            }
            @unlink($dir.DIRECTORY_SEPARATOR.$name);
        }
        @rmdir($dir);
    }

    private static function assertSafeDir(string $dir): void
    {
        if ($dir === '' || ! str_contains($dir, 'pr_idem_')) {
            throw new RuntimeException('Directorio de barrera inválido.');
        }
    }
}
