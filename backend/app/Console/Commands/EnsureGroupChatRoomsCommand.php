<?php

namespace App\Console\Commands;

use App\Domains\Chat\Services\SyncExistingGroupChatRoomsService;
use Illuminate\Console\Command;

class EnsureGroupChatRoomsCommand extends Command
{
    protected $signature = 'chat:ensure-rooms';

    protected $description = 'Crea salas de chat principales para juntas existentes (idempotente)';

    public function handle(SyncExistingGroupChatRoomsService $sync): int
    {
        $count = $sync->execute();
        $this->info("Procesadas {$count} juntas.");

        return self::SUCCESS;
    }
}
