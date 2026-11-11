<?php

namespace App\Domains\Chat\Services;

use App\Domains\Chat\Enums\ChatMessageReportStatus;
use App\Domains\Chat\Models\ChatMessageReport;
use App\Domains\Chat\Support\ChatMessageEventRecorder;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;

class ResolveChatMessageReportService
{
    public function __construct(private readonly ChatMessageEventRecorder $recorder) {}

    public function execute(
        ChatMessageReport $report,
        User $resolver,
        ChatMessageReportStatus $status,
        ?string $resolutionNote = null,
    ): ChatMessageReport {
        Gate::forUser($resolver)->authorize('resolve', $report);

        return DB::transaction(function () use ($report, $resolver, $status, $resolutionNote) {
            $report = ChatMessageReport::query()->whereKey($report->id)->lockForUpdate()->firstOrFail();
            $report->update([
                'status' => $status,
                'reviewed_by' => $resolver->id,
                'reviewed_at' => now(),
                'resolution_note' => $resolutionNote,
            ]);

            $message = $report->message()->first();
            if ($message) {
                $this->recorder->record($message, 'report_resolved', $resolver, $report->status->value, $status->value, [
                    'report_id' => $report->id,
                ]);
            }

            return $report->fresh();
        });
    }
}
