<?php

namespace App\Http\Controllers\Api\V1;

use App\Domains\Chat\Enums\ChatMessageStatus;
use App\Domains\Chat\Models\ChatMessage;
use App\Domains\Chat\Models\ChatRoom;
use App\Domains\Chat\Services\ChatUnreadCountService;
use App\Domains\Chat\Services\MarkChatRoomReadService;
use App\Domains\Chat\Services\SendChatMessageService;
use App\Domains\Chat\Support\ChatMembershipGuard;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Http\Controllers\Controller;
use App\Http\Resources\Api\V1\ChatMessageResource;
use App\Http\Resources\Api\V1\ChatRoomResource;
use App\Models\User;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class ChatRoomController extends Controller
{
    public function index(Request $request, ChatMembershipGuard $guard): AnonymousResourceCollection
    {
        /** @var User $user */
        $user = $request->user();
        $groupIds = $user->groupMemberships()
            ->where('status', MembershipStatus::Active)
            ->pluck('neighborhood_group_id');

        $rooms = ChatRoom::query()
            ->with('neighborhoodGroup')
            ->whereIn('neighborhood_group_id', $groupIds)
            ->orderBy('id')
            ->get()
            ->filter(fn (ChatRoom $room) => $guard->canReadRoom($user, $room))
            ->values();

        return ChatRoomResource::collection($rooms);
    }

    public function messages(Request $request, ChatRoom $room): AnonymousResourceCollection|JsonResponse
    {
        $this->authorize('view', $room);
        $request->validate([
            'after_id' => ['nullable', 'integer', 'min:1', 'prohibits:before_id'],
            'before_id' => ['nullable', 'integer', 'min:1', 'prohibits:after_id'],
            'limit' => ['nullable', 'integer', 'min:1', 'max:100'],
        ]);

        $limit = (int) ($request->input('limit', 30));
        $user = $request->user();
        $afterId = $request->filled('after_id') ? (int) $request->input('after_id') : null;
        $beforeId = $request->filled('before_id') ? (int) $request->input('before_id') : null;

        $query = ChatMessage::query()
            ->where('chat_room_id', $room->id)
            ->where('municipality_id', $room->municipality_id);

        $query->where(function ($builder) use ($user, $room) {
            $builder->where('status', ChatMessageStatus::Visible);
            $membership = $user->activeGroupMembershipFor($room->neighborhoodGroup);
            if ($membership?->canPerformGroupAdministration()) {
                $builder->orWhere('status', ChatMessageStatus::Hidden);
            }
            $builder->orWhere(function ($own) use ($user) {
                $own->where('sender_id', $user->id)
                    ->where('status', ChatMessageStatus::DeletedBySender);
            });
        });

        if ($afterId !== null) {
            $messages = $query->where('id', '>', $afterId)
                ->orderBy('id')
                ->limit($limit)
                ->get();
        } elseif ($beforeId !== null) {
            $messages = $query->where('id', '<', $beforeId)
                ->orderByDesc('id')
                ->limit($limit)
                ->get()
                ->reverse()
                ->values();
        } else {
            $messages = $query->orderByDesc('id')
                ->limit($limit)
                ->get()
                ->reverse()
                ->values();
        }

        return ChatMessageResource::collection($messages);
    }

    public function storeMessage(Request $request, ChatRoom $room, SendChatMessageService $send): JsonResponse
    {
        // view: 403 entre juntas. La escritura (sala bloqueada) sigue en el servicio → 422.
        $this->authorize('view', $room);
        $data = $this->validatedMessagePayload($request);

        $message = $send->execute(
            $room,
            $request->user(),
            $data['body'],
            $data['client_message_id'] ?? null,
        );

        return (new ChatMessageResource($message))->response()->setStatusCode(201);
    }

    public function unreadCount(ChatRoom $room, ChatUnreadCountService $unread): JsonResponse
    {
        $this->authorize('view', $room);

        return response()->json([
            'unread_count' => $unread->count($room, request()->user()),
        ]);
    }

    public function markRead(Request $request, ChatRoom $room, MarkChatRoomReadService $markRead): JsonResponse
    {
        $this->authorize('view', $room);
        $data = $request->validate([
            'last_read_message_id' => ['nullable', 'integer', 'min:1'],
        ]);

        $state = $markRead->execute($room, $request->user(), $data['last_read_message_id'] ?? null);

        return response()->json([
            'last_read_message_id' => $state->last_read_message_id,
            'last_read_at' => $state->last_read_at?->toIso8601String(),
        ]);
    }

    /**
     * @return array{body: string, client_message_id?: string}
     */
    private function validatedMessagePayload(Request $request): array
    {
        $maxLength = (int) config('red_vecinal.chat.max_message_length', 4000);
        $request->merge([
            'body' => trim((string) $request->input('body', '')),
        ]);

        return $request->validate([
            'body' => ['required', 'string', 'max:'.$maxLength],
            'client_message_id' => ['nullable', 'uuid'],
        ]);
    }
}
