<?php

namespace App\Domains\Posts\Support;

use App\Domains\Posts\Exceptions\PostReportIdempotencyException;
use Illuminate\Database\DeadlockException;
use Illuminate\Database\QueryException;
use Illuminate\Http\Request;
use Throwable;

/**
 * Contrato de Idempotency-Key para POST /api/v1/posts/{post}/reports.
 * Flutter 5E.4+ envía la cabecera y reutiliza la misma clave en «Comprobar envío».
 */
final class PostReportIdempotency
{
    public const HEADER = 'Idempotency-Key';

    /**
     * Intentos de la transacción idempotente ante deadlock 1213 o lock wait 1205.
     * No aplica a 409, 422, FK ni UNIQUE de otro índice.
     */
    public const TRANSIENT_ATTEMPTS = 3;

    /**
     * UUID v4 (RFC 4122): 8-4-4-4-12 hex, versión 4, variante 8/9/a/b.
     * Comparación insensible a mayúsculas; 5E.3 debe persistir en minúsculas.
     */
    public const KEY_PATTERN = '/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i';

    /**
     * Huella SHA-256 hexadecimal (64) del intento validado.
     *
     * Canonical JSON UTF-8, sin espacios, claves en este orden:
     * post_id, reason_code, details.
     *
     * - post_id: número JSON o null (no se convierte a string).
     * - reason_code: string exacto ya validado (sin trim ni cambio de mayúsculas).
     * - details: null JSON si el valor PHP es null; "" si el cliente envió string vacío.
     *   null y string vacío son huellas distintas.
     * - Sin NFC ni colapso de espacios: no altera la semántica del contrato actual.
     */
    public static function fingerprint(?int $postId, string $reasonCode, ?string $details): string
    {
        $canonical = json_encode(
            [
                'post_id' => $postId,
                'reason_code' => $reasonCode,
                'details' => $details,
            ],
            JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR,
        );

        return hash('sha256', $canonical);
    }

    public static function isValidKey(?string $key): bool
    {
        if ($key === null || $key === '') {
            return false;
        }

        return preg_match(self::KEY_PATTERN, $key) === 1;
    }

    public static function normalizeKey(string $key): string
    {
        return strtolower($key);
    }

    /**
     * @param  list<string|null>  $values
     */
    public static function keyFromHeaderValues(array $values): ?string
    {
        if ($values === []) {
            return null;
        }

        if (count($values) !== 1) {
            throw new PostReportIdempotencyException(
                'La cabecera Idempotency-Key debe enviarse una sola vez y ser un UUID v4 válido.',
                422,
            );
        }

        $raw = $values[0];
        if (! is_string($raw) || ! self::isValidKey($raw)) {
            throw new PostReportIdempotencyException(
                'La cabecera Idempotency-Key debe ser un UUID v4 válido.',
                422,
            );
        }

        return self::normalizeKey($raw);
    }

    public static function keyFromRequest(Request $request): ?string
    {
        return self::keyFromHeaderValues($request->headers->all(self::HEADER));
    }

    public static function isReporterKeyUniqueViolation(QueryException $exception): bool
    {
        $sqlState = (string) ($exception->errorInfo[0] ?? '');
        if ($sqlState !== '23000') {
            return false;
        }

        $driverCode = $exception->errorInfo[1] ?? null;
        if (in_array($driverCode, [1205, 1213, 1451, 1452], true)) {
            return false;
        }

        $message = $exception->getMessage();

        if (str_contains($message, 'post_reports_reporter_idempotency_unique')) {
            return true;
        }

        return str_contains($message, 'UNIQUE constraint failed')
            && str_contains($message, 'idempotency_key');
    }

    /**
     * Condición transitoria de locking InnoDB. No incluye 1062/23000 ni 409.
     * Incluye DeadlockException de Laravel (envoltorio de 1213 en transacción anidada).
     */
    public static function isTransientLockError(Throwable $exception): bool
    {
        if ($exception instanceof DeadlockException) {
            return true;
        }

        if (! $exception instanceof QueryException) {
            return false;
        }

        $driverCode = $exception->errorInfo[1] ?? null;
        if (in_array($driverCode, [1205, 1213], true)) {
            return true;
        }

        $sqlState = (string) ($exception->errorInfo[0] ?? '');
        if ($sqlState !== '40001') {
            return false;
        }

        $message = $exception->getMessage();

        return str_contains($message, '1213')
            || str_contains($message, 'Deadlock')
            || str_contains($message, '1205');
    }
}
