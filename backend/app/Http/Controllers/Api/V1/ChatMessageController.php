<?php

namespace App\Http\Controllers\Api\V1;

use App\Domains\Chat\Models\ChatMessage;
use App\Domains\Chat\Services\DeleteChatMessageService;
use App\Domains\Chat\Services\EditChatMessageService;
use App\Domains\Chat\Services\HideChatMessageService;
use App\Domains\Chat\Services\ReportChatMessageService;
use App\Http\Controllers\Controller;
use App\Http\Resources\Api\V1\ChatMessageResource;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class ChatMessageController extends Controller
{
    public function update(Request $request, ChatMessage $message, EditChatMessageService $edit): ChatMessageResource
    {
        $this->authorize('view', $message);
        $data = $request->validate([
            'body' => ['required', 'string'],
        ]);

        return new ChatMessageResource($edit->execute($message, $request->user(), $data['body']));
    }

    public function destroy(Request $request, ChatMessage $message, DeleteChatMessageService $delete): ChatMessageResource
    {
        $this->authorize('view', $message);

        return new ChatMessageResource($delete->execute($message, $request->user()));
    }

    public function hide(Request $request, ChatMessage $message, HideChatMessageService $hide): ChatMessageResource
    {
        $this->authorize('view', $message);
        $data = $request->validate(['reason' => ['nullable', 'string', 'max:500']]);

        return new ChatMessageResource($hide->execute($message, $request->user(), $data['reason'] ?? null));
    }

    public function report(Request $request, ChatMessage $message, ReportChatMessageService $report): JsonResponse
    {
        $this->authorize('view', $message);
        $data = $request->validate([
            'reason_code' => ['required', 'string', 'max:60'],
            'details' => ['nullable', 'string', 'max:2000'],
        ]);

        $created = $report->execute($message, $request->user(), $data['reason_code'], $data['details'] ?? null);

        return response()->json(['id' => $created->id], 201);
    }

    public function show(ChatMessage $message): ChatMessageResource
    {
        $this->authorize('view', $message);

        return new ChatMessageResource($message);
    }
}
