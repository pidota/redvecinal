# Roles y permisos — Fase 2

## Panel `/admin`

Solo entran usuarios con rol Spatie listado en `config/red_vecinal.php`:

- `super-admin`
- `administrador-municipal` **y** membresía activa en `municipality_members` con rol `administrador`

Presidentes, moderadores y vecinos **no** tienen acceso al panel en esta fase.

## Sincronización `municipality_members` ↔ Spatie

Al crear, editar o eliminar un registro en `municipality_members`, el observador ejecuta `MunicipalityMemberRoleSynchronizer`:

| Situación | Efecto sobre `administrador-municipal` |
|-----------|----------------------------------------|
| Membresía activa con rol `administrador` | Se asigna el rol Spatie (si no lo tiene) |
| Sin membresías activas `administrador` en ningún municipio | Se revoca `administrador-municipal` |
| Usuario con rol `super-admin` | El sincronizador **no modifica** `super-admin` |
| Rol `funcionario` | No otorga rol Spatie de panel |

Esto evita retirar permisos mientras el usuario siga siendo administrador en otra municipalidad.

### Reglas en Filament (personal municipal)

- Solo el **superadministrador** puede asignar el cargo `administrador`.
- Un administrador municipal puede gestionar **funcionarios** de su municipio, pero **no** su propia ficha ni elevarse a administrador.
- No se puede editar la membresía del superadministrador desde un admin municipal.

## Roles Spatie (catálogo)

| Rol | Uso |
|-----|-----|
| `super-admin` | Plataforma completa |
| `administrador-municipal` | Gestión municipal (requiere `municipality_members`) |
| `presidente-junta` | Reservado; autorización real vía `group_members` |
| `moderador-junta` | Reservado; autorización real vía `group_members` |
| `vecino` | Usuarios de app (futuro) |

## Permisos

Definidos en `RolesAndPermissionsSeeder` (`municipalities.view`, `neighborhood-groups.*`, `group-members.*`, `group-presidents.assign`, `chat.reports.view`, `chat.reports.resolve`, `chat.stats.view`).

### Chat (Fase 4)

| Permiso | Uso |
|---------|-----|
| `chat.reports.view` | Ver cola de reportes de mensajes (Filament); no acceso al chat completo |
| `chat.reports.resolve` | Resolver reportes y consultar contenido reportado (auditado) |
| `chat.stats.view` | Estadísticas agregadas (reservado) |

La participación en salas de junta **no** usa roles Spatie; usa `group_members` activos y `ChatMembershipGuard`.

## Autorización por junta

Las acciones sobre una junta concreta usan **Policies** y el estado en `group_members`, no roles Spatie globales de presidente/moderador.

| Acción | Superadmin | Admin municipal | Presidente | Moderador |
|--------|------------|-----------------|------------|-----------|
| CRUD juntas (Filament) | Sí | Su municipio | No | No |
| Aprobar / suspender | Sí | Su municipio | No | No |
| Incorporar integrantes | Sí | Su municipio | Su junta | No |
| Asignar presidente | Sí | Su municipio | No | No |

## Seeder

```bash
php artisan db:seed --class=RolesAndPermissionsSeeder
```

Idempotente; no elimina roles ya asignados a usuarios existentes.
