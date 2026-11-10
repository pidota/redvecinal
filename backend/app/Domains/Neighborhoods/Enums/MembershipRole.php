<?php

namespace App\Domains\Neighborhoods\Enums;

enum MembershipRole: string
{
    case President = 'president';
    case Moderator = 'moderator';
    case Member = 'member';
}
