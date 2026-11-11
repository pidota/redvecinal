<?php

namespace App\Console\Commands;

use App\Domains\Chat\Models\ChatRoom;
use App\Domains\Chat\Services\EnsureGroupChatRoomService;
use App\Domains\Chat\Services\SendChatMessageService;
use App\Domains\Neighborhoods\Enums\MembershipRole;
use App\Domains\Neighborhoods\Enums\MembershipStatus;
use App\Domains\Neighborhoods\Models\GroupMember;
use App\Domains\Neighborhoods\Models\NeighborhoodGroup;
use App\Models\User;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\Http;

/**
 * Smoke test local (HTTP): auth de canal Sanctum, envío API y verificación REST.
 * Para recibir el evento WS use un cliente Pusher/Reverb (ver docs/chat-tiempo-real.md).
 */
class ChatReverbSmokeCommand extends Command
{
    protected $signature = 'chat:reverb-smoke';

    protected $description = 'Smoke test local: Reverb activo, auth /broadcasting/auth, envío y lectura REST';

    public function handle(SendChatMessageService $send): int
    {
        $host = (string) env('REVERB_HOST', 'localhost');
        $port = (int) env('REVERB_PORT', 8080);
        $probeHost = $host === 'localhost' ? '127.0.0.1' : $host;

        if (! $this->portIsOpen($probeHost, $port)) {
            $this->error("Reverb no responde en {$host}:{$port}. Ejecute: php artisan reverb:start");

            return self::FAILURE;
        }

        [$room, $sender, $receiver, $receiverToken, $senderToken] = $this->provisionFixture();
        $channel = 'private-chat.room.'.$room->id;
        $socketId = random_int(100000, 999999).'.'.random_int(100000, 999999);

        $auth = $this->httpSanctum('post', '/broadcasting/auth', $receiverToken, [
            'channel_name' => $channel,
            'socket_id' => $socketId,
        ]);

        if (! $auth->successful()) {
            $this->error('Auth canal receptor: HTTP '.$auth->status().($auth->body() ? ' — '.mb_substr($auth->body(), 0, 200) : ''));

            return self::FAILURE;
        }
        $this->info('OK: receptor autorizado en '.$channel);

        $intruder = User::factory()->create();
        $denied = $this->httpSanctum('post', '/broadcasting/auth', $intruder->createToken('intruder')->plainTextToken, [
            'channel_name' => $channel,
            'socket_id' => random_int(100000, 999999).'.'.random_int(100000, 999999),
        ]);
        if ($denied->successful()) {
            $this->error('Fallo: usuario ajeno obtuvo auth de canal');

            return self::FAILURE;
        }
        $this->info('OK: usuario ajeno denegado en auth');

        $message = $send->execute($room, $sender, 'Smoke '.now()->timestamp);
        Artisan::call('queue:work', ['--once' => true, '--stop-when-empty' => true]);
        $this->info('OK: mensaje '.$message->id.' persistido (procese cola para emitir WS)');

        $listed = $this->httpSanctum('get', "/api/v1/chat/rooms/{$room->id}/messages", $receiverToken);

        if (! $listed->successful()) {
            $this->error('GET mensajes falló: '.$listed->status());

            return self::FAILURE;
        }

        $bodies = collect($listed->json('data'))->pluck('body');
        if (! $bodies->contains($message->body)) {
            $this->error('REST no devolvió el mensaje enviado');

            return self::FAILURE;
        }
        $this->info('OK: receptor recuperó contenido por REST (sin depender del payload WS)');

        $this->line('Conecte un cliente WS a ws://'.$host.':'.$port.' con la clave REVERB_APP_KEY y suscríbase a '.$channel.' usando auth anterior.');

        return self::SUCCESS;
    }

    /**
     * @return array{0: ChatRoom, 1: User, 2: User, 3: string, 4: string}
     */
    private function provisionFixture(): array
    {
        $group = NeighborhoodGroup::factory()->create();
        $sender = User::factory()->create();
        $receiver = User::factory()->create();

        foreach ([[$sender, MembershipRole::Member], [$receiver, MembershipRole::Member]] as [$user, $role]) {
            GroupMember::factory()->create([
                'neighborhood_group_id' => $group->id,
                'municipality_id' => $group->municipality_id,
                'user_id' => $user->id,
                'membership_role' => $role,
                'status' => MembershipStatus::Active,
            ]);
        }

        $room = app(EnsureGroupChatRoomService::class)->execute($group);

        return [
            $room,
            $sender,
            $receiver,
            $receiver->createToken('reverb-smoke-receiver')->plainTextToken,
            $sender->createToken('reverb-smoke-sender')->plainTextToken,
        ];
    }

    private function portIsOpen(string $host, int $port): bool
    {
        $connection = @fsockopen($host, $port, $errno, $errstr, 1);

        if (is_resource($connection)) {
            fclose($connection);

            return true;
        }

        return false;
    }

    /**
     * HTTP contra {@see config('app.url')} — debe usar la misma BD que el comando (tokens Sanctum).
     *
     * @param  array<string, mixed>  $payload
     */
    private function httpSanctum(string $method, string $path, string $token, array $payload = []): \Illuminate\Http\Client\Response
    {
        $base = rtrim((string) config('app.url'), '/');
        $request = Http::withToken($token)->acceptJson()->baseUrl($base);

        return $method === 'get'
            ? $request->get($path)
            : $request->post($path, $payload);
    }
}
