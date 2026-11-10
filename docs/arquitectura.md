# Arquitectura — Red Vecinal

## Visión

Monolito modular organizado por dominios de negocio, desplegado como una aplicación Laravel con una base de datos MySQL. La API móvil y futuras integraciones consumen REST bajo `/api/v1`. La administración municipal usa Filament en `/admin`.

## Principios

- **Una aplicación, una base de datos**: simplicidad operativa en Fase 1; multi-tenant completo se evaluará cuando existan dos o más municipios activos.
- **Separación de capas**: dominio (reglas), HTTP (controladores), presentación admin (Filament).
- **Autorización**: Laravel Policies + Spatie Permission para roles y permisos granulares.
- **Evolutivo**: dominio `Municipality` como ancla para futuro scoping por comuna.

## Estructura de directorios (backend)

```text
app/
├── Domains/
│   └── Municipality/
│       └── Models/
├── Filament/
├── Http/
│   └── Controllers/
│       └── Api/V1/          # (futuro)
├── Models/                   # User y modelos transversales
└── Providers/
```

## Autenticación

| Canal | Mecanismo |
|-------|-----------|
| API móvil / SPA | Laravel Sanctum (tokens) |
| Panel admin | Sesión web Filament + `FilamentUser::canAccessPanel()` y roles Spatie (`config/red_vecinal.php`) |

Detalle operativo: [acceso-panel-filament.md](acceso-panel-filament.md).

## Roadmap técnico (post Fase 1)

- Redis + Horizon para colas.
- Laravel Reverb para tiempo real.
- Firebase Cloud Messaging para push.
- Cliente Flutter en `mobile/`.

## Municipio inicial

Chépica se registra vía `MunicipalitySeeder` (`slug: chepica`). Otros municipios se agregarán con seeders o procesos de onboarding, sin reescribir el núcleo de la aplicación.

## Dominio Juntas (Fase 2)

- Modelos en `App\Domains\Neighborhoods\`.
- Reglas de negocio en servicios (`AssignPresidentService`, etc.).
- Filament para operadores municipales; autorización contextual en Policies.
- API `/api/v1/groups*` con Sanctum.

Ver [gestion-juntas.md](gestion-juntas.md) y [roles-permisos.md](roles-permisos.md).
