<?php

namespace App\Domains\Neighborhoods\Enums;

enum MembershipRequestStatus: string
{
    case Pending = 'pending';
    case Approved = 'approved';
    case Rejected = 'rejected';
    case Cancelled = 'cancelled';
}
