<?php

namespace App\Domains\Neighborhoods\Support;

use Illuminate\Database\QueryException;

final class MembershipRequestDatabase
{
    public static function isUniquePendingViolation(QueryException $e): bool
    {
        $message = $e->getMessage();

        return str_contains($message, 'neighborhood_membership_requests_unique_pending')
            || str_contains($message, 'Duplicate entry');
    }

    public static function isDuplicateGroupMember(QueryException $e): bool
    {
        $message = $e->getMessage();

        return str_contains($message, 'group_members.neighborhood_group_id')
            || (str_contains($message, 'Duplicate entry') && str_contains($message, 'group_members'));
    }

    public static function isDeadlock(QueryException $e): bool
    {
        $message = $e->getMessage();

        return str_contains($message, '1213')
            || str_contains($message, 'Deadlock')
            || str_contains($message, '40001');
    }

    public static function isRetriableConflict(QueryException $e): bool
    {
        return self::isUniquePendingViolation($e)
            || self::isDuplicateGroupMember($e)
            || self::isDeadlock($e);
    }
}
