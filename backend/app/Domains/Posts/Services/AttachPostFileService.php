<?php

namespace App\Domains\Posts\Services;

use App\Domains\Posts\Exceptions\PostDomainException;
use App\Domains\Posts\Models\PostAttachment;
use App\Domains\Posts\Models\PostRevision;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

class AttachPostFileService
{
    public function execute(PostRevision $revision, User $uploader, UploadedFile $file): PostAttachment
    {
        $post = $revision->post;
        if ($post->author_id !== $uploader->id) {
            throw new PostDomainException('Solo el autor puede adjuntar archivos a esta revisión.');
        }

        if ($revision->isPublishedSnapshot()) {
            throw new PostDomainException('No puede adjuntar archivos a la revisión publicada sin crear una nueva revisión.');
        }

        $count = $revision->attachments()->count();
        $max = (int) config('red_vecinal.posts.max_attachments_per_revision', 5);
        if ($count >= $max) {
            throw new PostDomainException("Máximo de {$max} adjuntos por revisión.");
        }

        $maxKb = (int) config('red_vecinal.posts.max_attachment_size_kb', 5120);
        if ($file->getSize() > $maxKb * 1024) {
            throw new PostDomainException('El archivo excede el tamaño permitido.');
        }

        $finfo = new \finfo(FILEINFO_MIME_TYPE);
        $mime = $finfo->file($file->getRealPath()) ?: $file->getMimeType();
        $allowed = config('red_vecinal.posts.allowed_attachment_mimes', []);
        if (! in_array($mime, $allowed, true)) {
            throw new PostDomainException('Tipo de archivo no permitido.');
        }

        if (str_contains($file->getClientOriginalName(), '..') || str_contains($file->getClientOriginalName(), '/')) {
            throw new PostDomainException('Nombre de archivo no válido.');
        }

        $extension = match ($mime) {
            'image/jpeg' => 'jpg',
            'image/png' => 'png',
            'image/webp' => 'webp',
            'application/pdf' => 'pdf',
            default => 'bin',
        };

        $disk = config('red_vecinal.posts.disk', 'posts_private');
        $path = sprintf(
            '%d/%d/%s.%s',
            $post->municipality_id,
            $post->id,
            (string) Str::uuid(),
            $extension,
        );

        Storage::disk($disk)->putFileAs(
            dirname($path),
            $file,
            basename($path),
        );

        return PostAttachment::query()->create([
            'post_revision_id' => $revision->id,
            'post_id' => $post->id,
            'municipality_id' => $post->municipality_id,
            'uploaded_by' => $uploader->id,
            'disk' => $disk,
            'path' => $path,
            'original_display_name' => Str::limit($file->getClientOriginalName(), 200, ''),
            'mime_type' => $mime,
            'size_bytes' => $file->getSize(),
            'checksum' => hash_file('sha256', $file->getRealPath()),
        ]);
    }
}
