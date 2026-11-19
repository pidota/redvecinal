<?php

namespace App\Domains\Posts\Exceptions;

class PostReportIdempotencyException extends PostDomainException
{
    public function __construct(
        string $message,
        public readonly int $httpStatus = 422,
    ) {
        parent::__construct($message);
    }
}
