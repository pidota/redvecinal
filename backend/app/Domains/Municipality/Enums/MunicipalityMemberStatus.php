<?php

namespace App\Domains\Municipality\Enums;

enum MunicipalityMemberStatus: string
{
    case Active = 'active';
    case Inactive = 'inactive';
}
