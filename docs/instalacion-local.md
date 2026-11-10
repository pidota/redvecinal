# Instalación local — Red Vecinal

Entorno recomendado: **Windows 11 + Laragon + Cursor**.

## Requisitos

- PHP 8.3 o superior (extensiones estándar de Laravel).
- Composer 2.x.
- MySQL 8.4 (incluido en Laragon).
- Node.js 22 LTS (assets Filament / Vite).
- Git.

## Rutas del proyecto

- Carpeta: `D:\laragon\www\red-vecinal` (o equivalente en `www`).
- Virtual host sugerido: `red-vecinal.test` apuntando a `backend/public`.

## Pasos

### 1. Base de datos

```sql
CREATE DATABASE IF NOT EXISTS red_vecinal
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;
```

### 2. Backend Laravel

```bash
cd backend
composer install
cp .env.example .env   # en Windows: copy .env.example .env
php artisan key:generate
php artisan migrate
php artisan db:seed
```

### 3. Usuario administrador Filament

No existe registro público en `/admin`. Crear usuario:

```bash
php artisan make:filament-user
```

### 4. Verificación

```bash
php artisan --version
php artisan migrate:status
php artisan route:list
php artisan test
```

Probar en navegador:

- `http://red-vecinal.test/up`
- `http://red-vecinal.test/admin/login`
- `http://red-vecinal.test/api/v1/health`

## Zona horaria e idioma

- `APP_LOCALE=es`
- `APP_TIMEZONE=America/Santiago`

## Problemas frecuentes

| Síntoma | Solución |
|---------|----------|
| Error de conexión MySQL | Verificar que MySQL esté iniciado en Laragon |
| 404 en dominio `.test` | Crear o recargar virtual hosts en Laragon |
| Panel sin estilos | `php artisan filament:assets` |
