# Laravel Reverb en Laragon — guía reproducible

Validación manual de WebSockets en **desarrollo local** (Fase 4). No aplica a producción/VPS.

## 1. Requisitos previos

| Componente | Referencia en este equipo |
|------------|---------------------------|
| PHP | 8.3+ (Laragon) |
| Laravel | 13.x |
| MySQL | 8.4 (BD `red_vecinal`, migraciones al día) |
| Node.js | 22+ y `npm` |
| Laragon | Apache + vhost `http://red-vecinal.test` → `backend/public` |
| Composer | Dependencia `laravel/reverb` ^1.13 |

Tabla `jobs` (driver `database`) obligatoria para broadcasting encolado.

## 2. Variables de entorno (sin secretos reales en Git)

Plantilla en `backend/.env.example`. En `.env` local (no versionar):

```ini
BROADCAST_CONNECTION=reverb
QUEUE_CONNECTION=database
APP_URL=http://red-vecinal.test

REVERB_APP_ID=<generado con php artisan reverb:install>
REVERB_APP_KEY=<generado>
REVERB_APP_SECRET=<generado>
REVERB_HOST=localhost
REVERB_PORT=8080
REVERB_SCHEME=http

# Servidor que escucha (artisan reverb:start)
REVERB_SERVER_HOST=0.0.0.0
REVERB_SERVER_PORT=8080
```

**Coherencia:** el cliente (Pusher/Echo) usa `REVERB_HOST` + `REVERB_PORT` + `REVERB_SCHEME`. Laravel publica hacia el mismo endpoint. El servidor WS escucha en `REVERB_SERVER_HOST:REVERB_SERVER_PORT` (p. ej. `0.0.0.0:8080`). Reverb **no** pasa por el virtual host HTTP de Laragon.

## 3. Laragon

- Document root: `D:\laragon\www\red-vecinal\backend\public`.
- Entrada `hosts`: `127.0.0.1 red-vecinal.test`.
- `Invoke-WebRequest http://red-vecinal.test/up` → 200.

## 4. Iniciar servicios (tres terminales)

```powershell
cd D:\laragon\www\red-vecinal\backend
php artisan optimize:clear
php artisan migrate:status
```

**Terminal A — Reverb**

```powershell
php artisan reverb:start
# opcional: php artisan reverb:start --debug
```

**Terminal B — colas (broadcasting)**

```powershell
php artisan queue:work --tries=3
```

**Terminal C — verificación HTTP**

```powershell
php artisan chat:reverb-smoke
```

Comprobar que el puerto WS esté libre/ocupado solo por Reverb (`netstat -ano | findstr :8080`).

## 5. E2E WebSocket automatizado

Ruta: `backend/scripts/dev/reverb-e2e/`.

```powershell
cd D:\laragon\www\red-vecinal\backend\scripts\dev\reverb-e2e
npm install
php prepare-fixture.php fixture.json
node run.mjs fixture.json
# Suite completa (10 escenarios + revocación):
node run-all-scenarios.mjs fixture.json
del fixture.json
```

**Atención:** `prepare-fixture.php` inserta usuarios y juntas **ficticios** en la base configurada en `.env`. No usar contra datos de producción. Usuarios con dominio `@example.test`.

## 6. Canales privados

- Nombre Echo: `private-chat.room.{roomId}`.
- Autorización: `POST /broadcasting/auth` con `Authorization: Bearer {token Sanctum}`.
- Regla: membresía **activa** en la junta de la sala (`ChatMembershipGuard::canReadRoom`).

## 7. Errores frecuentes

| Síntoma | Causa probable | Acción |
|---------|----------------|--------|
| Timeout `chat.sync` | Sin `queue:work` o Reverb detenido | Iniciar cola y Reverb |
| Auth 403 esperado | Usuario sin membresía / suspendido | Revisar `group_members.status` |
| Auth 500 puntual | Carga concurrente / caché | `optimize:clear`, reintentar |
| WS no conecta | `REVERB_HOST=localhost` desde Node | Script usa `127.0.0.1` |
| `fixture.json` con BOM | Redirección PowerShell | Escribir con `php prepare-fixture.php fixture.json` |
| Smoke OK pero sin WS | Smoke solo valida HTTP + cola `--once` | Usar `run.mjs` o cliente real |
| `chat:reverb-smoke` HTTP 500 en auth | Registro en `storage/logs/laravel.log`: Sanctum buscó `personal_access_tokens` en **sqlite** (`database.sqlite`) mientras el token se creó en MySQL — p. ej. petición atendida con otra config de BD que la del `artisan` | Alinear `APP_URL`/vhost con la misma BD que el CLI; no ejecutar smoke en paralelo con `php artisan test` |

## 8. Detener procesos

- `Ctrl+C` en terminales de `reverb:start` y `queue:work`.
- No eliminar filas de `jobs` ni hacer `queue:clear` salvo diagnóstico autorizado.

## 9. Limitaciones conocidas (Fase 4)

- El payload WS **no** incluye contenido del mensaje (solo `room_id`, `message_id`, `event_type`, `version`).
- **No** hay expulsión inmediata de sockets al suspender un vecino; nuevas suscripciones y REST sí se bloquean; reconexión vuelve a validar en `/broadcasting/auth`.
- Junta **suspendida**: envío bloqueado; historial y **nueva suscripción al canal** siguen permitidos para miembros activos (solo lectura).
- Producción/Reverb en VPS: fuera de alcance hasta autorización explícita.

## 10. Referencias

- `docs/chat-tiempo-real.md`
- `docs/seguridad-chat.md`
- `docs/instalacion-local.md`
