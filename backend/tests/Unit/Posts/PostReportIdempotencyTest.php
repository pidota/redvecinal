<?php

namespace Tests\Unit\Posts;

use App\Domains\Posts\Exceptions\PostReportIdempotencyException;
use App\Domains\Posts\Support\PostReportIdempotency;
use Illuminate\Database\QueryException;
use PDOException;
use PHPUnit\Framework\Attributes\DataProvider;
use Tests\TestCase;

class PostReportIdempotencyTest extends TestCase
{
    public function test_fingerprint_is_deterministic_and_hex_sha256(): void
    {
        $first = PostReportIdempotency::fingerprint(12, 'spam', 'Detalle');
        $second = PostReportIdempotency::fingerprint(12, 'spam', 'Detalle');

        $this->assertSame($first, $second);
        $this->assertSame(64, strlen($first));
        $this->assertMatchesRegularExpression('/^[0-9a-f]{64}$/', $first);
    }

    public function test_null_details_differs_from_empty_string(): void
    {
        $withNull = PostReportIdempotency::fingerprint(1, 'spam', null);
        $withEmpty = PostReportIdempotency::fingerprint(1, 'spam', '');

        $this->assertNotSame($withNull, $withEmpty);
        $this->assertSame(
            hash('sha256', '{"post_id":1,"reason_code":"spam","details":null}'),
            $withNull,
        );
        $this->assertSame(
            hash('sha256', '{"post_id":1,"reason_code":"spam","details":""}'),
            $withEmpty,
        );
    }

    public function test_does_not_trim_or_fold_validated_values(): void
    {
        $plain = PostReportIdempotency::fingerprint(1, 'spam', 'Hola');
        $paddedReason = PostReportIdempotency::fingerprint(1, ' spam', 'Hola');
        $paddedDetails = PostReportIdempotency::fingerprint(1, 'spam', ' Hola');
        $upperReason = PostReportIdempotency::fingerprint(1, 'Spam', 'Hola');

        $this->assertNotSame($plain, $paddedReason);
        $this->assertNotSame($plain, $paddedDetails);
        $this->assertNotSame($plain, $upperReason);
    }

    public function test_utf8_is_preserved_without_unicode_escape(): void
    {
        $fingerprint = PostReportIdempotency::fingerprint(3, 'inappropriate', 'Niño ñoño');

        $this->assertSame(
            hash('sha256', '{"post_id":3,"reason_code":"inappropriate","details":"Niño ñoño"}'),
            $fingerprint,
        );
    }

    public function test_null_post_id_is_json_null_not_string(): void
    {
        $this->assertSame(
            hash('sha256', '{"post_id":null,"reason_code":"spam","details":null}'),
            PostReportIdempotency::fingerprint(null, 'spam', null),
        );
    }

    public function test_field_order_is_post_id_reason_code_details(): void
    {
        $canonical = '{"post_id":9,"reason_code":"spam","details":"x"}';
        $reordered = '{"reason_code":"spam","post_id":9,"details":"x"}';

        $this->assertSame(
            hash('sha256', $canonical),
            PostReportIdempotency::fingerprint(9, 'spam', 'x'),
        );
        $this->assertNotSame(
            hash('sha256', $reordered),
            PostReportIdempotency::fingerprint(9, 'spam', 'x'),
        );
    }

    #[DataProvider('validUuidV4Provider')]
    public function test_accepts_uuid_v4(string $key): void
    {
        $this->assertTrue(PostReportIdempotency::isValidKey($key));
        $this->assertSame(strtolower($key), PostReportIdempotency::normalizeKey($key));
    }

    /**
     * @return array<string, array{0: string}>
     */
    public static function validUuidV4Provider(): array
    {
        return [
            'lowercase' => ['550e8400-e29b-41d4-a716-446655440000'],
            'uppercase' => ['550E8400-E29B-41D4-A716-446655440000'],
            'variant_8' => ['123e4567-e89b-42d3-8456-426614174000'],
            'variant_b' => ['123e4567-e89b-42d3-b456-426614174000'],
        ];
    }

    #[DataProvider('invalidKeyProvider')]
    public function test_rejects_non_uuid_v4(?string $key): void
    {
        $this->assertFalse(PostReportIdempotency::isValidKey($key));
    }

    /**
     * @return array<string, array{0: ?string}>
     */
    public static function invalidKeyProvider(): array
    {
        return [
            'null' => [null],
            'empty' => [''],
            'uuid_v1' => ['550e8400-e29b-11d4-a716-446655440000'],
            'no_hyphens' => ['550e8400e29b41d4a716446655440000'],
            'random' => ['not-a-uuid'],
            'too_short' => ['550e8400-e29b-41d4-a716-44665544000'],
            'leading_space' => [' 550e8400-e29b-41d4-a716-446655440000'],
            'trailing_space' => ['550e8400-e29b-41d4-a716-446655440000 '],
        ];
    }

    public function test_absent_header_values_yield_null(): void
    {
        $this->assertNull(PostReportIdempotency::keyFromHeaderValues([]));
    }

    public function test_empty_header_is_invalid_not_legacy(): void
    {
        $this->expectException(PostReportIdempotencyException::class);
        $this->expectExceptionMessage('UUID v4');
        PostReportIdempotency::keyFromHeaderValues(['']);
    }

    public function test_multiple_header_values_are_rejected(): void
    {
        $this->expectException(PostReportIdempotencyException::class);
        PostReportIdempotency::keyFromHeaderValues([
            '550e8400-e29b-41d4-a716-446655440000',
            '123e4567-e89b-42d3-a456-426614174000',
        ]);
    }

    public function test_header_is_normalized_after_validation(): void
    {
        $this->assertSame(
            '550e8400-e29b-41d4-a716-446655440000',
            PostReportIdempotency::keyFromHeaderValues(['550E8400-E29B-41D4-A716-446655440000']),
        );
    }

    public function test_sqlite_unique_message_is_detected(): void
    {
        $exception = $this->queryException(
            '23000',
            19,
            'SQLSTATE[23000]: Integrity constraint violation: 19 UNIQUE constraint failed: post_reports.reporter_id, post_reports.idempotency_key',
        );

        $this->assertTrue(PostReportIdempotency::isReporterKeyUniqueViolation($exception));
    }

    public function test_mysql_duplicate_on_idempotency_index_is_detected(): void
    {
        $exception = $this->queryException(
            '23000',
            1062,
            "SQLSTATE[23000]: Integrity constraint violation: 1062 Duplicate entry '1-550e8400-e29b-41d4-a716-446655440000' for key 'post_reports_reporter_idempotency_unique'",
        );

        $this->assertTrue(PostReportIdempotency::isReporterKeyUniqueViolation($exception));
    }

    public function test_foreign_key_and_other_uniques_are_not_idempotency(): void
    {
        $foreignKey = $this->queryException(
            '23000',
            1452,
            'SQLSTATE[23000]: Integrity constraint violation: 1452 Cannot add or update a child row: a foreign key constraint fails',
        );
        $otherUnique = $this->queryException(
            '23000',
            1062,
            "SQLSTATE[23000]: Integrity constraint violation: 1062 Duplicate entry '1' for key 'users_email_unique'",
        );
        $deadlock = $this->queryException('40001', 1213, 'Deadlock found when trying to get lock');

        $this->assertFalse(PostReportIdempotency::isReporterKeyUniqueViolation($foreignKey));
        $this->assertFalse(PostReportIdempotency::isReporterKeyUniqueViolation($otherUnique));
        $this->assertFalse(PostReportIdempotency::isReporterKeyUniqueViolation($deadlock));
    }

    private function queryException(string $sqlState, int $driverCode, string $message): QueryException
    {
        $previous = new PDOException($message, $driverCode);
        $previous->errorInfo = [$sqlState, $driverCode, $message];

        return new QueryException('sqlite', 'insert into "post_reports"', [], $previous);
    }
}
