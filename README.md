# Red Vecinal

Plataforma de comunicación, organización comunitaria y seguridad vecinal para municipalidades de Chile. La primera implementación operativa está orientada a la **Municipalidad de Chépica** (Región de O'Higgins), con arquitectura preparada para incorporar otras comunas en el futuro.

## Estructura del repositorio

```text
red-vecinal/
├── backend/     # API y panel administrativo (Laravel 13)
├── mobile/      # App Flutter (fases posteriores)
├── docs/        # Documentación técnica
├── AGENTS.md    # Reglas para asistentes de código (Cursor)
└── README.md
```

## Stack (Fase 1)

| Componente | Versión |
|------------|---------|
| PHP | 8.3+ |
| Laravel | 13.x |
| Filament | 5.x |
| MySQL | 8.4 |
| Laravel Sanctum | 4.x |
| Spatie Laravel Permission | 8.x |

## Inicio rápido (Laragon)

1. Clonar el repositorio en `www/red-vecinal`.
2. Crear la base de datos `red_vecinal` (utf8mb4).
3. Copiar `backend/.env.example` a `backend/.env`, configurar MySQL y ejecutar `php artisan key:generate`.
4. Desde `backend/`:
   ```bash
   composer install
   php artisan migrate
   php artisan db:seed
   ```
5. Crear usuario administrador (no hay registro público):
   ```bash
   php artisan make:filament-user
   ```

## URLs locales

| Servicio | URL |
|----------|-----|
| Aplicación | `http://red-vecinal.test` (o virtual host de Laragon) |
| Panel Filament | `http://red-vecinal.test/admin` |
| API v1 health | `http://red-vecinal.test/api/v1/health` |

## Documentación

- [Arquitectura](docs/arquitectura.md)
- [Base de datos](docs/base-de-datos.md)
- [Instalación local](docs/instalacion-local.md)

## Repositorio remoto

`https://github.com/pidota/redvecinal.git` — rama principal: `main`.
