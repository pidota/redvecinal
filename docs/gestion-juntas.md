# Gestión de juntas de vecinos

## Modelo

- **NeighborhoodGroup:** junta asociada a una `municipality_id`.
- **GroupMember:** vínculo usuario–junta con `membership_role` (`president`, `moderator`, `member`) y `status`.
- **Integridad:** FK compuesta `(neighborhood_group_id, municipality_id)` y columna generada `active_president_key` (un presidente activo por junta).

## Estados de junta

| Estado | Administración |
|--------|----------------|
| `active` | Incorporaciones, aprobaciones y cambios de presidente |
| `inactive` / `suspended` | Bloqueadas para acciones comunitarias |

## Flujos administrativos (Filament)

1. **Juntas de vecinos:** crear, editar, filtrar por municipio/estado.
2. **Integrantes (Relation Manager):**
   - Agregar usuario existente o crear uno nuevo.
   - Aprobar / rechazar solicitudes pendientes.
   - Suspender o retirar integrantes.
   - **Asignar presidente** (solo administradores municipales con permiso o superadministrador).
3. **Personal municipal:** vincular usuarios a Chépica con rol `administrador` o `funcionario`.
   - El rol Spatie `administrador-municipal` se sincroniza automáticamente al guardar membresías `administrador` activas.
   - Tras crear un administrador municipal nuevo, verificar acceso a `/admin` (debe tener rol Spatie + membresía activa).

## Reglas clave

- El presidente **no** asigna presidentes ni modifica su propio cargo administrativo.
- El moderador **no** aprueba, suspende ni expulsa por defecto.
- Un usuario puede ser presidente de **varias juntas**, con una presidencia activa por junta.
- Eliminación lógica de juntas solo sin integrantes activos.

## Servicios de dominio

Ubicados en `App\Domains\Neighborhoods\Services\`. Toda asignación de presidente pasa por `AssignPresidentService`.

## API (Sanctum)

| Ruta | Descripción |
|------|-------------|
| `GET /api/v1/groups` | Listado según permisos / membresías |
| `GET /api/v1/groups/{id}` | Detalle (sin teléfono/correo de contacto en JSON) |
| `GET /api/v1/me/groups` | Juntas del usuario autenticado |
| `GET /api/v1/groups/{id}/members` | Integrantes activos (datos acotados) |
