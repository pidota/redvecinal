# Herramienta de desarrollo — E2E WebSocket Reverb

**No usar en producción.** Carpeta temporal para validar Fase 4 en Laragon.

## Requisitos

- `php artisan reverb:start` (terminal 1)
- `php artisan queue:work` (terminal 2)
- `BROADCAST_CONNECTION=reverb` y `APP_URL` accesible desde Node (p. ej. `http://red-vecinal.test`)

## Ejecución

```powershell
cd backend\scripts\dev\reverb-e2e
npm install
php prepare-fixture.php fixture.json
node run.mjs fixture.json
```

Eliminar `fixture.json` tras la prueba (contiene tokens).
