<?php

namespace App\Domains\Chat\Enums;

enum ChatMessageReportStatus: string
{
    case Open = 'open';
    case Reviewing = 'reviewing';
    case Resolved = 'resolved';
    case Dismissed = 'dismissed';
}
