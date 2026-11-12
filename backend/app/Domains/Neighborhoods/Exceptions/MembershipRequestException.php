<?php

namespace App\Domains\Neighborhoods\Exceptions;

class MembershipRequestException extends NeighborhoodDomainException
{
    public function __construct(
        string $message,
        public readonly int $httpStatus = 422,
    ) {
        parent::__construct($message);
    }
}
