# AGENTS.md — Red Vecinal

Instrucciones para asistentes de código (Cursor y similares) que trabajen en este repositorio.

## Propósito del proyecto

Monolito modular Laravel para gestión vecinal municipal. Multi-municipalidad preparada a nivel de datos; la Fase 1 solo opera con Chépica.

## Arquitectura

- Código de negocio bajo `backend/app/Domains/{Dominio}/` (modelos, acciones, políticas).
- Controladores API en `backend/app/Http/Controllers/Api/V1/`.
- Recursos Filament en `backend/app/Filament/` (sin lógica de negocio pesada).
- API REST versionada: prefijo **`/api/v1`**.
- Una sola base de datos MySQL compartida.

## Reglas obligatorias

1. **Alcance**: no modificar dominios o funcionalidades ajenas a la tarea solicitada.
2. **Base de datos**: usar migraciones; nunca `migrate:fresh`, `db:wipe`, `DROP DATABASE` ni operaciones destructivas sin autorización explícita.
3. **Multi-municipalidad**: no codificar IDs fijos de municipio en lógica reutilizable; usar `municipality_id` o contexto resoluble cuando aplique.
4. **Seguridad**: validar entradas; usar Policies y Spatie Permission; no exponer secretos en código versionado.
5. **Pruebas**: agregar o actualizar tests PHPUnit para nueva funcionalidad con comportamiento verificable.
6. **Filament**: panel en `/admin`; sin registro público de administradores.
7. **Despliegue**: no ejecutar deploy, push ni cambios en producción sin autorización del responsable del proyecto.
8. **Dependencias**: no instalar paquetes innecesarios; respetar Laravel 13 y Filament 5.

## Fuera de alcance (hasta nueva fase)

- Laravel Reverb, Horizon, Redis en producción, FCM, app Flutter completa.
- Juntas de vecinos, publicaciones, chat y alertas de emergencia.

## Comandos útiles

```bash
cd backend
php artisan migrate:status
php artisan test
php artisan route:list
```
