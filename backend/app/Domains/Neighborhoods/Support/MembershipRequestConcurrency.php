<?php

namespace App\Domains\Neighborhoods\Support;

use App\Domains\Neighborhoods\Exceptions\MembershipRequestException;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;

/**
 * Transacciones de solicitudes con reintento explícito ante deadlocks MySQL (1213 / 40001).
 */
final class MembershipRequestConcurrency
{
    public const DEFAULT_ATTEMPTS = 3;

    private static bool $deadlockReconcile = false;

    public static function shouldReconcileDeadlock(): bool
    {
        return self::$deadlockReconcile;
    }

    /**
     * @template T
     *
     * @param  callable(): T  $callback
     * @return T
     */
    public static function runTransactional(callable $callback, int $attempts = self::DEFAULT_ATTEMPTS): mixed
    {
        $attempts = max(1, $attempts);
        $lastDeadlock = null;

        for ($attempt = 1; $attempt <= $attempts; $attempt++) {
            self::$deadlockReconcile = $attempt > 1;

            try {
                $result = DB::transaction($callback);
                self::$deadlockReconcile = false;

                return $result;
            } catch (MembershipRequestException $e) {
                self::$deadlockReconcile = false;

                throw $e;
            } catch (QueryException $e) {
                if (! MembershipRequestDatabase::isDeadlock($e)) {
                    self::$deadlockReconcile = false;

                    throw $e;
                }

                $lastDeadlock = $e;

                if ($attempt >= $attempts) {
                    self::$deadlockReconcile = false;

                    throw $e;
                }

                usleep(random_int(10_000, 40_000) * $attempt);
            }
        }

        self::$deadlockReconcile = false;

        throw $lastDeadlock;
    }
}