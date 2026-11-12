<?php

use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\ChatMessageController;
use App\Http\Controllers\Api\V1\ChatRoomController;
use App\Http\Controllers\Api\V1\MembershipRequestController;
use App\Http\Controllers\Api\V1\NeighborhoodGroupController;
use App\Http\Controllers\Api\V1\PostAttachmentController;
use App\Http\Controllers\Api\V1\PostCommentController;
use App\Http\Controllers\Api\V1\PostController;
use App\Http\Controllers\Api\V1\PostReactionController;
use App\Http\Controllers\Api\V1\PostReportController;
use Illuminate\Support\Facades\Route;

Route::post('/auth/login', [AuthController::class, 'login'])
    ->middleware('throttle:mobile-login');

Route::get('/health', function () {
    return response()->json([
        'status' => 'ok',
        'application' => config('app.name'),
        'version' => 'v1',
    ]);
});

Route::middleware('auth:sanctum')->group(function () {
    Route::post('/auth/logout', [AuthController::class, 'logout']);
    Route::get('/me', [AuthController::class, 'me']);

    Route::get('/groups', [NeighborhoodGroupController::class, 'index']);
    Route::get('/groups/{group}', [NeighborhoodGroupController::class, 'show']);
    Route::get('/me/groups', [NeighborhoodGroupController::class, 'myGroups']);
    Route::get('/me/reviewable-groups', [NeighborhoodGroupController::class, 'reviewableGroups']);
    Route::get('/groups/{group}/members', [NeighborhoodGroupController::class, 'members']);
    Route::get('/groups/{group}/membership-context', [MembershipRequestController::class, 'membershipContext']);
    Route::post('/groups/{group}/membership-requests', [MembershipRequestController::class, 'store'])
        ->middleware('throttle:membership-requests');
    Route::get('/groups/{group}/membership-requests', [MembershipRequestController::class, 'indexForGroup']);

    Route::get('/me/membership-requests', [MembershipRequestController::class, 'myIndex']);
    Route::delete('/me/membership-requests/{membershipRequest}', [MembershipRequestController::class, 'destroy']);

    Route::post('/membership-requests/{membershipRequest}/approve', [MembershipRequestController::class, 'approve']);
    Route::post('/membership-requests/{membershipRequest}/reject', [MembershipRequestController::class, 'reject']);

    Route::get('/posts', [PostController::class, 'index']);
    Route::get('/me/posts', [PostController::class, 'mine']);
    Route::post('/posts', [PostController::class, 'store']);
    Route::get('/posts/{post}', [PostController::class, 'show']);
    Route::patch('/posts/{post}', [PostController::class, 'update']);
    Route::post('/posts/{post}/submit', [PostController::class, 'submit']);
    Route::post('/posts/{post}/approve', [PostController::class, 'approve']);
    Route::post('/posts/{post}/reject', [PostController::class, 'reject']);
    Route::post('/posts/{post}/hide', [PostController::class, 'hide']);
    Route::post('/posts/{post}/restore', [PostController::class, 'restore']);
    Route::post('/posts/{post}/archive', [PostController::class, 'archive']);
    Route::get('/groups/{group}/posts/pending', [PostController::class, 'pendingForGroup']);

    Route::get('/posts/{post}/comments', [PostCommentController::class, 'index']);
    Route::post('/posts/{post}/comments', [PostCommentController::class, 'store']);
    Route::put('/posts/{post}/reactions', [PostReactionController::class, 'update']);
    Route::delete('/posts/{post}/reactions', [PostReactionController::class, 'destroy']);
    Route::post('/posts/{post}/reports', [PostReportController::class, 'store']);
    Route::post('/posts/{post}/attachments', [PostAttachmentController::class, 'store']);
    Route::get('/posts/{post}/attachments/{attachment}', [PostAttachmentController::class, 'show']);

    Route::get('/chat/rooms', [ChatRoomController::class, 'index']);
    Route::get('/chat/rooms/{room}/messages', [ChatRoomController::class, 'messages']);
    Route::post('/chat/rooms/{room}/messages', [ChatRoomController::class, 'storeMessage']);
    Route::get('/chat/rooms/{room}/unread-count', [ChatRoomController::class, 'unreadCount']);
    Route::post('/chat/rooms/{room}/read', [ChatRoomController::class, 'markRead']);

    Route::get('/chat/messages/{message}', [ChatMessageController::class, 'show']);
    Route::patch('/chat/messages/{message}', [ChatMessageController::class, 'update']);
    Route::delete('/chat/messages/{message}', [ChatMessageController::class, 'destroy']);
    Route::post('/chat/messages/{message}/hide', [ChatMessageController::class, 'hide']);
    Route::post('/chat/messages/{message}/report', [ChatMessageController::class, 'report']);
});
