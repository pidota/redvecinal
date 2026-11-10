<?php

namespace App\Http\Controllers\Api\V1;

use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Services\ReportPostService;
use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;

class PostReportController extends Controller
{
    public function store(Request $request, Post $post, ReportPostService $report): JsonResponse
    {
        if (! Gate::forUser($request->user())->allows('view', $post)) {
            abort(404);
        }

        $this->authorize('report', $post);

        $data = $request->validate([
            'reason_code' => ['required', 'string', 'max:60'],
            'details' => ['nullable', 'string', 'max:2000'],
        ]);

        $record = $report->execute(
            $request->user(),
            $data['reason_code'],
            $post,
            null,
            $data['details'] ?? null,
        );

        return response()->json(['id' => $record->id, 'status' => $record->status->value], 201);
    }
}
