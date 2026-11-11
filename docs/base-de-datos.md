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

## Tablas principales

Además de las tablas estándar de Laravel (usuarios, sesiones, caché, jobs):

| Tabla | Origen |
|-------|--------|
| `personal_access_tokens` | Laravel Sanctum |
| `permissions`, `roles`, pivots | Spatie Permission |
| `municipalities` | Dominio Municipality |
| `municipality_members` | Personal municipal |
| `neighborhood_groups` | Juntas de vecinos |
| `group_members` | Integrantes (FK compuesta + índice único presidente) |
| `group_membership_events` | Auditoría de cambios |
| `post_categories` | Categorías de publicación |
| `posts` | Publicaciones (estado global) |
| `post_revisions` | Contenido versionado |
| `post_attachments` | Adjuntos por revisión |
| `post_comments`, `post_reactions`, `post_reports` | Interacción |
| `post_moderation_events` | Auditoría de moderación |
| `chat_rooms` | Sala principal por junta (única por `neighborhood_group_id`) |
| `chat_messages` | Mensajes (idempotencia `client_message_id`) |
| `chat_message_reports` | Reportes vecinales |
| `chat_message_events` | Auditoría de mensajes |
| `chat_read_states` | Marcador de lectura por usuario y sala |

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

- **MunicipalitySeeder**: Chépica (idempotente).
- **RolesAndPermissionsSeeder**: roles y permisos Fase 2 (idempotente).

## Comandos seguros

```bash
php artisan migrate
php artisan migrate:status
php artisan db:seed
```

No usar `migrate:fresh` ni `db:wipe` en entornos con datos reales.
