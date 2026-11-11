<?php

namespace App\Filament\Resources\ChatMessageReports\Pages;

use App\Filament\Resources\ChatMessageReports\ChatMessageReportResource;
use Filament\Resources\Pages\ListRecords;

class ListChatMessageReports extends ListRecords
{
    protected static string $resource = ChatMessageReportResource::class;
}
