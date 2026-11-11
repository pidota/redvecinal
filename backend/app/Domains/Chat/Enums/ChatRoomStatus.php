<?php

namespace App\Domains\Chat\Enums;

enum ChatRoomStatus: string
{
    case Active = 'active';
    case Locked = 'locked';
    case Archived = 'archived';
}
