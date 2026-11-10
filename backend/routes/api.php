<?php

use App\Http\Controllers\Api\V1\NeighborhoodGroupController;
use Illuminate\Support\Facades\Route;

Route::get('/health', function () {
    return response()->json([
        'status' => 'ok',
        'application' => config('app.name'),
        'version' => 'v1',
    ]);
});

Route::middleware('auth:sanctum')->group(function () {
    Route::get('/groups', [NeighborhoodGroupController::class, 'index']);
    Route::get('/groups/{group}', [NeighborhoodGroupController::class, 'show']);
    Route::get('/me/groups', [NeighborhoodGroupController::class, 'myGroups']);
    Route::get('/groups/{group}/members', [NeighborhoodGroupController::class, 'members']);
});
