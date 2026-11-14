<?php

namespace App\Http\Resources\Api\V1;

use App\Domains\Posts\Models\PostAttachment;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin PostAttachment */
class PostAttachmentResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->id,
            'revision_id' => $this->post_revision_id,
            'original_display_name' => $this->original_display_name,
            'mime_type' => $this->mime_type,
            'size_bytes' => $this->size_bytes,
            'download_url' => '/api/v1/posts/'.$this->post_id.'/attachments/'.$this->id,
        ];
    }
}