<?php

namespace App\Domains\Chat\Services;

use App\Domains\Chat\Enums\ChatMessageReportStatus;
use App\Domains\Chat\Models\ChatMessage;
use App\Domains\Chat\Models\ChatMessageReport;
use App\Domains\Chat\Support\ChatMembershipGuard;
use App\Domains\Chat\Support\ChatMessageEventRecorder;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;

class ReportChatMessageService
{
    public function __construct(
        private readonly ChatMembershipGuard $guard,
        private readonly ChatMessageEventRecorder $recorder,
    ) {}

    public function execute(ChatMessage $message, User $reporter, string $reasonCode, ?string $details = null): ChatMessageReport
    {
        Gate::forUser($reporter)->authorize('report', $message);
        $message->loadMissing('room.neighborhoodGroup');
        $this->guard->assertCanReadRoom($reporter, $message->room);

        return DB::transaction(function () use ($message, $reporter, $reasonCode, $details) {
            $report = ChatMessageReport::query()->firstOrCreate(
                [
                    'chat_message_id' => $message->id,
                    'reporter_id' => $reporter->id,
                ],
                [
                    'municipality_id' => $message->municipality_id,
                    'reason_code' => $reasonCode,
                    'details' => $details,
                    'status' => ChatMessageReportStatus::Open,
                ],
            );

            if ($report->wasRecentlyCreated) {
                $this->recorder->record($message, 'reported', $reporter, null, null, [
                    'report_id' => $report->id,
                    'reason_code' => $reasonCode,
                ]);
            }

            return $report;
        });
    }
}
