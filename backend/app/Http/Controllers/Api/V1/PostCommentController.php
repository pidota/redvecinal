<?php

namespace App\Http\Controllers\Api\V1;

use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostComment;
use App\Domains\Posts\Services\AddCommentService;
use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;

class PostCommentController extends Controller
{
    public function index(Request $request, Post $post): JsonResponse
    {
        if (! Gate::forUser($request->user())->allows('view', $post)) {
            abort(404);
        }

        $comments = $post->comments()
            ->where('status', 'visible')
            ->orderBy('created_at')
            ->paginate();

        return response()->json($comments);
    }

    public function store(Request $request, Post $post, AddCommentService $add): JsonResponse
    {
        $this->authorize('comment', $post);

        $data = $request->validate([
            'body' => ['required', 'string', 'max:5000'],
        ]);

        $comment = $add->execute($post, $request->user(), $data['body']);

        return response()->json($comment, 201);
    }
}
