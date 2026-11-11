<?php

namespace App\Domains\Chat\Enums;

enum ChatSyncEventType: string
{
    case MessageCreated = 'message_created';
    case MessageUpdated = 'message_updated';
    case MessageDeleted = 'message_deleted';
    case MessageModerated = 'message_moderated';
}
