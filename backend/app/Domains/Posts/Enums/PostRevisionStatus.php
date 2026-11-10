<?php

namespace App\Domains\Posts\Enums;

enum PostRevisionStatus: string
{
    case Draft = 'draft';
    case Pending = 'pending';
    case Approved = 'approved';
    case Rejected = 'rejected';
    case Superseded = 'superseded';
}
