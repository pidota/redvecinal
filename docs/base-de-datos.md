# Base de datos — Red Vecinal

## Motor y codificación

- **Motor**: MySQL 8.4 (Laragon).
- **Base de datos**: `red_vecinal`.
- **Charset / collation**: `utf8mb4` / `utf8mb4_unicode_ci`.

## Conexión local (desarrollo)

Configurar en `backend/.env` (no versionar):

```ini
DB_CONNECTION=mysql
DB_HOST=127.0.0.1
DB_PORT=3306
DB_DATABASE=red_vecinal
DB_USERNAME=root
DB_PASSWORD=
```

## Tablas (Fase 1)

Además de las tablas estándar de Laravel (usuarios, sesiones, caché, jobs):

| Tabla | Origen |
|-------|--------|
| `personal_access_tokens` | Laravel Sanctum |
| `permissions`, `roles`, pivots | Spatie Permission |
| `municipalities` | Dominio Municipality |

### `municipalities`

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `id` | bigint | PK |
| `name` | string | Nombre legal o institucional |
| `slug` | string, único | Identificador estable (ej. `chepica`) |
| `region_code` | string | Código región (ej. `06` O'Higgins) |
| `commune_code` | string | Código comuna (ej. `06302`) |
| `status` | string | Ej. `active`, `inactive` |
| `settings` | json, nullable | Configuración flexible por municipio |
| `created_at`, `updated_at` | timestamps | |

## Seeders

- **MunicipalitySeeder**: crea o actualiza Chépica (`updateOrCreate` por `slug`), idempotente.

## Comandos seguros

```bash
php artisan migrate
php artisan migrate:status
php artisan db:seed
```

No usar `migrate:fresh` ni `db:wipe` en entornos con datos reales.
