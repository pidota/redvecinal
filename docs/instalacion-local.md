# Instalación local — Red Vecinal

Entorno validado: **Windows 11 + Laragon** (ruta real del proyecto en este equipo).

## Ubicación del proyecto

| Concepto | Ruta |
|----------|------|
| Raíz del monorepo | `D:\laragon\www\red-vecinal` |
| Document root (Laravel) | `D:\laragon\www\red-vecinal\backend\public` |
| Código backend | `D:\laragon\www\red-vecinal\backend` |
| MySQL (Laragon) | `D:\laragon\bin\mysql\mysql-8.4.3-winx64\bin\mysql.exe` |

> Nota: La documentación histórica mencionaba `C:\laragon\www`; en este entorno Laragon está en **`D:\laragon`**.

## Virtual host `red-vecinal.test`

Laragon genera vhosts automáticos hacia la carpeta del proyecto (`www/nombre`), pero este monorepo exige apuntar al **`public` de Laravel**.

Archivo creado (solo Red Vecinal):

`D:\laragon\etc\apache2\sites-enabled\auto.red-vecinal.test.conf`

```apache
DocumentRoot "D:/laragon/www/red-vecinal/backend/public"
ServerName red-vecinal.test
```

### Activar el sitio

1. **Entrada DNS local** (si Laragon no la agregó solo):
   - Abrir Laragon como **Administrador** → *Menu* → *Apache* → *Reload*, o
   - Añadir manualmente en `C:\Windows\System32\drivers\etc\hosts`:
     ```
     127.0.0.1      red-vecinal.test     #laragon magic!
     ```
2. **Recargar Apache** desde Laragon: *Menu* → *Apache* → *Reload* (o *Stop All* → *Start All*).
3. Confirmar `APP_URL` en `backend/.env`:
   ```ini
   APP_URL=http://red-vecinal.test
   ```

### Verificación rápida (sin hosts, opcional)

```powershell
Invoke-WebRequest -Uri "http://127.0.0.1/up" -Headers @{ Host = "red-vecinal.test" }
```

## Requisitos

- PHP 8.3+ (`D:\laragon\bin\php\php-8.3.30-Win32-vs16-x64\php.exe`)
- Composer 2.x
- MySQL 8.4.3
- Node.js 22 (Laragon: `D:\laragon\bin\nodejs`)

## Base de datos

```powershell
& "D:\laragon\bin\mysql\mysql-8.4.3-winx64\bin\mysql.exe" -u root -e "CREATE DATABASE IF NOT EXISTS red_vecinal CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;"
```

Credenciales locales solo en `backend/.env` (no versionar).

## Backend

```powershell
cd D:\laragon\www\red-vecinal\backend
composer install
copy .env.example .env
php artisan key:generate
php artisan migrate
php artisan db:seed
```

## Usuario administrador Filament

```powershell
cd D:\laragon\www\red-vecinal\backend
php artisan make:filament-user
```

Luego asignar un rol de panel (ver [acceso-panel-filament.md](acceso-panel-filament.md)). Sin rol, el login responderá **403** aunque la contraseña sea correcta.

## Comandos de validación (Fase 1)

```powershell
cd D:\laragon\www\red-vecinal\backend
php artisan --version
php artisan migrate:status
php artisan route:list
php artisan test
```

URLs en navegador (con vhost activo):

- `http://red-vecinal.test/up`
- `http://red-vecinal.test/admin/login`
- `http://red-vecinal.test/api/v1/health`

## Archivos que no deben ir a Git

- `backend/.env`
- `backend/database/*.sqlite`
- `backend/vendor/`
- Cachés PHPUnit (ver `.gitignore`)

## Problemas frecuentes

| Síntoma | Solución |
|---------|----------|
| `red-vecinal.test` no resuelve | Entrada en `hosts` + recarga Apache |
| 404 en raíz del monorepo | DocumentRoot debe ser `backend/public`, no `red-vecinal` |
| 403 tras login Filament | Asignar rol `super-admin` o `administrador-municipal` |
| Error MySQL | Iniciar MySQL en Laragon |
