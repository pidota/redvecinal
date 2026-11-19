<?php

namespace App\Domains\Posts\Services;

use App\Domains\Posts\Enums\PostReportStatus;
use App\Domains\Posts\Exceptions\PostReportIdempotencyException;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostComment;
use App\Domains\Posts\Models\PostReport;
use App\Domains\Posts\Support\PostReportIdempotency;
use App\Models\User;
use Illuminate\Database\QueryException;
use Illuminate\Support\Facades\DB;

class ReportPostService
{
    public function execute(
        User $reporter,
        string $reasonCode,
        ?Post $post = null,
        ?PostComment $comment = null,
        ?string $details = null,
        ?string $idempotencyKey = null,
    ): PostReport {
        if ($idempotencyKey === null) {
            return $this->insertOpenReport(
                $reporter,
                $reasonCode,
                $post,
                $comment,
                $details,
                null,
                null,
            );
        }

        $fingerprint = PostReportIdempotency::fingerprint($post?->id, $reasonCode, $details);

        return DB::transaction(function () use ($reporter, $reasonCode, $post, $comment, $details, $idempotencyKey, $fingerprint) {
            $existing = $this->findKeyedReportForUpdate($reporter->id, $idempotencyKey);
            if ($existing !== null) {
                return $this->sameAttemptOrConflict($existing, $post?->id, $fingerprint);
            }

            try {
                return $this->insertOpenReport(
                    $reporter,
                    $reasonCode,
                    $post,
                    $comment,
                    $details,
                    $idempotencyKey,
                    $fingerprint,
                );
            } catch (QueryException $exception) {
                if (! PostReportIdempotency::isReporterKeyUniqueViolation($exception)) {
                    throw $exception;
                }

                $existing = $this->findKeyedReportForUpdate($reporter->id, $idempotencyKey);
                if ($existing === null) {
                    throw $exception;
                }

                return $this->sameAttemptOrConflict($existing, $post?->id, $fingerprint);
            }
        });
    }

    protected function findKeyedReportForUpdate(int $reporterId, string $idempotencyKey): ?PostReport
    {
        return PostReport::query()
            ->where('reporter_id', $reporterId)
            ->where('idempotency_key', $idempotencyKey)
            ->lockForUpdate()
            ->first();
    }

    protected function insertOpenReport(
        User $reporter,
        string $reasonCode,
        ?Post $post,
        ?PostComment $comment,
        ?string $details,
        ?string $idempotencyKey,
        ?string $fingerprint,
    ): PostReport {
        $municipalityId = $post?->municipality_id ?? $comment?->municipality_id;

        return PostReport::query()->create([
            'post_id' => $post?->id,
            'post_comment_id' => $comment?->id,
            'municipality_id' => $municipalityId,
            'reporter_id' => $reporter->id,
            'reason_code' => $reasonCode,
            'details' => $details,
            'status' => PostReportStatus::Open,
            'idempotency_key' => $idempotencyKey,
            'payload_fingerprint' => $fingerprint,
        ]);
    }

    protected function sameAttemptOrConflict(PostReport $existing, ?int $postId, string $fingerprint): PostReport
    {
        $existingPostId = $existing->post_id === null ? null : (int) $existing->post_id;

        if ($existingPostId !== $postId || $existing->payload_fingerprint !== $fingerprint) {
            throw new PostReportIdempotencyException(
                'La clave de idempotencia ya fue usada con otro contenido.',
                409,
            );
        }

        return $existing;
    }
}
