<?php

namespace App\Domains\Posts\Services;

use App\Domains\Posts\Enums\PostReportStatus;
use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostComment;
use App\Domains\Posts\Models\PostReport;
use App\Models\User;

class ReportPostService
{
    public function execute(
        User $reporter,
        string $reasonCode,
        ?Post $post = null,
        ?PostComment $comment = null,
        ?string $details = null,
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
        ]);
    }
}
