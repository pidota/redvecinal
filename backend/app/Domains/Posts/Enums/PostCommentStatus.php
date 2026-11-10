<?php

namespace App\Domains\Posts\Enums;

enum PostCommentStatus: string
{
    case Visible = 'visible';
    case Hidden = 'hidden';
    case Removed = 'removed';
}
