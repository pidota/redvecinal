<?php

namespace App\Domains\Chat\Services;

use App\Domains\Chat\Models\ChatMessage;
use App\Domains\Chat\Models\ChatMessageReport;
use App\Domains\Chat\Support\ChatMessageEventRecorder;
use App\Models\User;
use Illuminate\Support\Facades\Gate;

class ViewReportedChatMessageService
{
    public function __construct(private readonly ChatMessageEventRecorder $recorder) {}

    public function execute(ChatMessageReport $report, User $viewer): ChatMessage
    {
        $message = $report->message()->firstOrFail();
        Gate::forUser($viewer)->authorize('viewReportedContent', $message);

        $this->recorder->record($message, 'supervisor_viewed', $viewer, null, null, [
            'report_id' => $report->id,
        ]);

        return $message->load('sender');
    }
}
