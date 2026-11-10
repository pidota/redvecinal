<?php

namespace App\Http\Controllers\Api\V1;

use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Services\ReactToPostService;
use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class PostReactionController extends Controller
{
    public function update(Request $request, Post $post, ReactToPostService $react): JsonResponse
    {
        $this->authorize('react', $post);

        $data = $request->validate([
            'type' => ['sometimes', 'string', 'max:30'],
        ]);

        $reaction = $react->execute($post, $request->user(), $data['type'] ?? 'like');

        return response()->json($reaction);
    }

    public function destroy(Request $request, Post $post, ReactToPostService $react): JsonResponse
    {
        $this->authorize('react', $post);
        $react->remove($post, $request->user());

        return response()->json(['deleted' => true]);
    }
}
