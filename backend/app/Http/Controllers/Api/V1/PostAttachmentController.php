<?php

namespace App\Http\Controllers\Api\V1;

use App\Domains\Posts\Models\Post;
use App\Domains\Posts\Models\PostAttachment;
use App\Domains\Posts\Models\PostRevision;
use App\Domains\Posts\Services\AttachPostFileService;
use App\Http\Controllers\Controller;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\StreamedResponse;

class PostAttachmentController extends Controller
{
    public function store(Request $request, Post $post, AttachPostFileService $attach): JsonResponse
    {
        $this->authorize('update', $post);

        $data = $request->validate([
            'revision_id' => ['required', 'integer', 'exists:post_revisions,id'],
            'file' => ['required', 'file'],
        ]);

        $revision = PostRevision::query()
            ->where('post_id', $post->id)
            ->whereKey($data['revision_id'])
            ->firstOrFail();

        $attachment = $attach->execute($revision, $request->user(), $data['file']);

        return response()->json([
            'id' => $attachment->id,
            'revision_id' => $attachment->post_revision_id,
            'original_display_name' => $attachment->original_display_name,
            'mime_type' => $attachment->mime_type,
            'size_bytes' => $attachment->size_bytes,
        ], 201);
    }

    public function show(Request $request, Post $post, PostAttachment $attachment): StreamedResponse
    {
        $attachment = PostAttachment::query()
            ->whereKey($attachment->id)
            ->where('post_id', $post->id)
            ->firstOrFail();

        if (str_contains($attachment->path, '..')) {
            abort(404);
        }

        if (! Gate::forUser($request->user())->allows('viewAttachment', [$post, $attachment->post_revision_id])) {
            abort(404);
        }

        return Storage::disk($attachment->disk)->response(
            $attachment->path,
            $attachment->original_display_name,
            ['Content-Type' => $attachment->mime_type],
        );
    }
}
