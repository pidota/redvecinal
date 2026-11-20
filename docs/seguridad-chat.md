# Seguridad del chat — Fase 4

## Contenido fuera de WebSocket

Los eventos de sincronización **no transportan** `body`, nombres, correos, teléfonos ni metadatos de reportes. El cliente debe llamar a la API REST, que valida membresía en cada solicitud.

Ejemplo de payload broadcast (`ChatRoomSyncBroadcast::broadcastWith()`):

```json
{
  "room_id": 1,
  "message_id": 42,
  "event_type": "message_created",
  "version": 1
}
```

## Autorización de canales

- Ruta de canal: `private-chat.room.{id}` (Echo) ↔ `chat.room.{id}` en `routes/channels.php`.
- Criterio: membresía **activa** en la junta de la sala (`ChatMembershipGuard::canReadRoom`).
- Sanctum identifica al usuario en `/broadcasting/auth` cuando el driver de broadcasting implementa autenticación (p. ej. Reverb/Pusher/Redis).

### Autenticación HTTP de canales

- Ruta `POST /broadcasting/auth` protegida con **`auth:sanctum`** (`bootstrap/app.php`).
- El callback en `routes/channels.php` usa `ChatMembershipGuard::canReadRoom` (membresía activa en la junta).
- Los canales se registran al final del boot de la aplicación; en pruebas de auth PHPUnit se re-registran sobre el driver Pusher de prueba.

### Revocación de suscripciones (limitación explícita)

- Autorizar el canal en el handshake **no revoca** conexiones WebSocket ya abiertas si luego se suspende al vecino o la junta.
- Cada **reconexión** vuelve a llamar a `/broadcasting/auth` y revalida membresía.
- REST y nuevas autorizaciones de canal **sí rechazan** al usuario revocado (membresía activa).
- Un socket previamente autorizado **puede seguir recibiendo** señales `chat.sync` (sin `body`) después de perder la membresía.
- **No** hay desconexión forzada del servidor en 5.5.2; el problema **no está resuelto**. Pendiente para **5.5.6** (contrato de cliente) y **5.5.8** (cierre de canal / hardening WS).

## Moderación y privacidad municipal

- Presidente/moderador activos pueden **ocultar** mensajes ajenos; permanecen en BD para auditoría pero no en el historial visible de vecinos.
- Administradores municipales **no** tienen lector general del chat.
- Acceso al contenido vía reportes: permisos `chat.reports.view` / `chat.reports.resolve` y servicios auditados (`ViewReportedChatMessageService`); el superadministrador no recibe acceso automático al chat privado.

## Integridad referencial

FK compuestas y únicos en migraciones `2026_11_10_300000`–`300004` (sala↔junta↔municipio, mensaje↔sala, idempotencia `client_message_id`, lecturas por usuario/sala).

## Pruebas

- `tests/Feature/Chat/ChatBroadcastTest.php` — payload sin contenido sensible.
- `tests/Feature/Chat/ChatChannelAuthorizationTest.php` — misma lógica que `channels.php` (driver `null` en CI).
- `tests/Feature/Chat/ChatHttpContractTest.php` — validación 422, abilities de mutación, throttle de envío, aislamiento.
- Aislamiento entre juntas/municipios cubierto en tests de mensajería y policies.

## Rate limit de envío (5.5.2)

- Middleware `throttle:chat-send` solo en `POST /api/v1/chat/rooms/{room}/messages`.
- Clave por usuario autenticado (`chat-send|{userId}`); lecturas, edición, borrado, hide y reportes **no** comparten este cupo.
- Tope inicial MVP: **30 mensajes/minuto** (`red_vecinal.chat.send_per_user_per_minute`), alineado en orden de magnitud con `mobile_auth.login_attempts_per_ip_per_minute` (30/min) y más estricto que un chat libre.
- Respuesta `429` sin crear fila. Los reintentos idempotentes **no** eluden el límite.
