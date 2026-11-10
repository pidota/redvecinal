<?php

namespace App\Domains\Posts\Support;

use Illuminate\Support\Str;

class MarkdownRenderer
{
    public function toSafeHtml(string $markdown): string
    {
        return Str::markdown($markdown, [
            'html_input' => 'strip',
            'allow_unsafe_links' => false,
        ]);
    }
}
