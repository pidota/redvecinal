# Chat grupal en tiempo real — Fase 4

## Alcance

- Una sala principal (`chat_rooms`) por junta (`neighborhood_groups`), creada al crear la junta o con `php artisan chat:ensure-rooms`.
- Mensajes de **texto plano** (sin Markdown/HTML renderizado en servidor).
- API REST con **Laravel Sanctum**; sincronización en cliente vía eventos WebSocket mínimos + fetch REST del contenido.
- Sin adjuntos ni notificaciones push en esta versión.

## Dominio

`App\Domains\Chat`: modelos, enums, policies, servicios, `ChatSyncEventDispatcher`, `ChatRoomSyncBroadcast`, auditoría en `chat_message_events`.

### Emisión post-commit (único mecanismo)

Dentro de la transacción del servicio se llama a `ChatSyncEventDispatcher`, que dispara `ChatRoomSyncBroadcast` con la propiedad **`$afterCommit = true`**. No se usa `DB::afterCommit` adicional: Laravel encola el `BroadcastEvent` solo tras commit exitoso.

## API (`/api/v1`, `auth:sanctum`)

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/chat/rooms` | Salas de juntas con membresía activa |
| GET | `/chat/rooms/{room}/messages` | Historial incremental (`after_id`, `before_id`, `limit`) |
| POST | `/chat/rooms/{room}/messages` | Enviar mensaje (`body`, `client_message_id` UUID opcional) |
| GET | `/chat/rooms/{room}/unread-count` | No leídos (excluye propios y ocultos/eliminados) |
| POST | `/chat/rooms/{room}/read` | Actualizar `chat_read_states` |
| GET | `/chat/messages/{message}` | Detalle (membresía + policy) |
| PATCH | `/chat/messages/{message}` | Edición por autor (ventana configurada) |
| DELETE | `/chat/messages/{message}` | Borrado lógico por autor |
| POST | `/chat/messages/{message}/hide` | Ocultar (presidente/moderador, mensaje ajeno) |
| POST | `/chat/messages/{message}/report` | Reportar mensaje |

Autenticación de canales: `POST /broadcasting/auth` con middleware **`auth:sanctum`** (configurado en `bootstrap/app.php` → `withBroadcasting`).

## Junta suspendida / sala solo lectura

Si la junta no está activa, la sala permanece en historial **solo lectura** para miembros con acceso de lectura: GET, marcadores de lectura y **suscripción al canal** siguen permitidos para miembros activos; envío, edición y borrado devuelven 422.

## Idempotencia

`client_message_id` + `sender_id` + `chat_room_id` es único en base de datos. Reintentos devuelven el mismo mensaje **sin** volver a encolar broadcasting.

## Comandos

```bash
php artisan chat:ensure-rooms    # backfill salas
php artisan chat:reverb-smoke    # smoke HTTP local (auth + REST)
```

## Laravel Reverb (solo desarrollo local)

1. Copiar variables de `backend/.env.example` y ejecutar `php artisan reverb:install` (genera credenciales **solo en `.env` local**, no versionar).
2. En `.env` local:

```ini
BROADCAST_CONNECTION=reverb
QUEUE_CONNECTION=database
```

Redis **no** es obligario en este entorno (no detectado en Laragon); las colas usan la tabla `jobs`.

3. Tres terminales:

```powershell
cd D:\laragon\www\red-vecinal\backend
php artisan reverb:start
php artisan queue:work
# Apache/Laragon ya sirve red-vecinal.test
```

4. Smoke automatizado (auth Sanctum + envío + lectura REST):

```powershell
php artisan chat:reverb-smoke
```

5. Cliente WebSocket (Pusher/Reverb): conectar a `ws://{REVERB_HOST}:{REVERB_PORT}/app/{REVERB_APP_KEY}`, suscribirse a `private-chat.room.{id}` usando la respuesta de `/broadcasting/auth` (`Authorization: Bearer {token}`). Evento: **`chat.sync`** (payload sin `body`). Luego `GET /api/v1/chat/rooms/{room}/messages`.

### E2E automatizado (desarrollo)

Herramienta temporal en `backend/scripts/dev/reverb-e2e/` (`README.md`): `pusher-js` + `prepare-fixture.php` + `run.mjs`. Requiere Reverb y `queue:work` activos. No versionar `fixture.json` (tokens).

### Pruebas PHPUnit

- Driver `BROADCAST_CONNECTION=null` en `phpunit.xml` (sin Redis).
- `ChatBroadcastAfterCommitTest`, `ChatBroadcastTest`, `ChatBroadcastingAuthTest` cubren commit, payload y `/broadcasting/auth`.
- La integración WS completa no sustituye a un cliente real; use `chat:reverb-smoke` + cliente Echo/Pusher en local.

## Filament

- Listado de reportes de chat (`chat.reports.view` / `chat.reports.resolve`).
- No hay visor municipal del chat completo.

## Configuración

`config/red_vecinal.php` → clave `chat` (`max_message_length`, `edit_window_minutes`).
`config/reverb.php` → servidor local (producción: variables en servidor, fuera del repo).
