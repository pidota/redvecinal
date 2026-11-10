<?php

namespace App\Domains\Posts\Enums;

enum PostStatus: string
{
    case Draft = 'draft';
    case Pending = 'pending';
    case Published = 'published';
    case Rejected = 'rejected';
    case Hidden = 'hidden';
    case Archived = 'archived';

    public function allowsPublicInteraction(): bool
    {
        return $this === self::Published;
    }
}
