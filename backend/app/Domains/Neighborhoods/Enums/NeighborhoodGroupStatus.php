<?php

namespace App\Domains\Neighborhoods\Enums;

enum NeighborhoodGroupStatus: string
{
    case Active = 'active';
    case Inactive = 'inactive';
    case Suspended = 'suspended';
}
