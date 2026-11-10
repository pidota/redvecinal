<?php

namespace App\Domains\Posts\Enums;

enum PostVisibility: string
{
    case MembersOnly = 'members_only';
    case MunicipalFeed = 'municipal_feed';
}
