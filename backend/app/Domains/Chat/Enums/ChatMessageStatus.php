<?php

namespace App\Domains\Chat\Enums;

enum ChatMessageStatus: string
{
    case Visible = 'visible';
    case Hidden = 'hidden';
    case DeletedBySender = 'deleted_by_sender';
}
