<?php

namespace App\Domains\Posts\Enums;

enum PostReportStatus: string
{
    case Open = 'open';
    case Reviewing = 'reviewing';
    case Resolved = 'resolved';
    case Dismissed = 'dismissed';

    public function label(): string
    {
        return match ($this) {
            self::Open => 'Abierto',
            self::Reviewing => 'En revisión',
            self::Resolved => 'Resuelto',
            self::Dismissed => 'Descartado',
        };
    }

    public function color(): string
    {
        return match ($this) {
            self::Open => 'warning',
            self::Reviewing => 'info',
            self::Resolved => 'success',
            self::Dismissed => 'gray',
        };
    }
}
