# API móvil — Juntas de vecinos

Prefijo: `/api/v1`. Autenticación: **Bearer Sanctum** en todas las rutas de este documento.

## GET `/me/groups`

Juntas en las que el usuario autenticado tiene **membresía activa** (`group_members.status = active`). Incluye juntas cuyo estado sea `inactive` o `suspended` si la membresía sigue activa.

**Parámetros:** ninguno.

**Respuesta 200:**

```json
{
  "data": [
    {
      "id": 1,
      "municipality_id": 10,
      "name": "Junta Centro",
      "slug": "junta-centro",
      "description": "…",
      "address": "…",
      "status": "active",
      "municipality": {
        "id": 10,
        "name": "Municipalidad de Chépica",
        "slug": "chepica"
      }
    }
  ]
}
```

El objeto `municipality` aparece cuando la relación fue cargada en el servidor (`id`, `name`, `slug` únicamente).

**Errores:**

| HTTP | Causa |
|------|--------|
| 401 | Sin token o token inválido |

## Recurso compartido `NeighborhoodGroup`

Usado también en `GET /groups`, `GET /groups/{id}` (Fase 5.3.2+).

| Campo | Tipo | Notas |
|-------|------|--------|
| `id` | int | |
| `municipality_id` | int | |
| `name` | string | |
| `slug` | string | |
| `description` | string\|null | |
| `address` | string\|null | |
| `status` | string | `active`, `inactive`, `suspended` |
| `municipality` | object\|omitido | `id`, `name`, `slug` |

**No expuesto:** `contact_email`, `contact_phone`, `registration_number`, `settings`.

## Estados de junta

| `status` | Significado |
|----------|-------------|
| `active` | Administrable en panel |
| `inactive` / `suspended` | Sin administración comunitaria en panel; pueden seguir listándose en API si la membresía es activa |

## GET `/groups/{group}/membership-context`

Información descriptiva mínima de una junta **sin membresía activa** del usuario, para decidir si solicitar incorporación. No sustituye a `GET /groups/{id}` (solo miembros activos / administradores).

**Errores:** 401, 403 (sin acceso móvil, junta no elegible o fuera de ámbito municipal).

## Solicitudes de incorporación

Rate limit en creación: `throttle:membership-requests` (config `red_vecinal.membership_requests.store_per_user_per_hour`, por defecto 20/h por usuario e IP).

| Método | Ruta | Descripción |
|--------|------|-------------|
| POST | `/groups/{group}/membership-requests` | Crear solicitud (`request_note` opcional, máx. 500) |
| GET | `/me/membership-requests` | Listado paginado del solicitante |
| DELETE | `/me/membership-requests/{request}` | Cancelar solicitud propia (solo `pending`) |
| GET | `/groups/{group}/membership-requests` | Listado paginado para revisores autorizados |
| POST | `/membership-requests/{request}/approve` | Aprobar (`review_note` opcional) |
| POST | `/membership-requests/{request}/reject` | Rechazar (`review_note` opcional) |

**Recurso `MembershipRequest`:** `id`, `status` (`pending`, `approved`, `rejected`, `cancelled`), `neighborhood_group_id`, `request_note`, `review_note` (solo revisores), fechas ISO8601, `neighborhood_group` (cuando aplique), `requester` (`id`, `name` solo para listados de revisión).

**Errores habituales:**

| HTTP | Situación |
|------|-----------|
| 401 | Sin Sanctum |
| 403 | Policy (revisor, junta suspendida, fuera de municipio, etc.) |
| 404 | Recurso inexistente |
| 409 | Conflicto: duplicado `pending`, ya miembro activo, `group_members.pending` Filament, re-aprobación |
| 422 | Validación o cooldown de 7 días tras rechazo (`rejection_cooldown_days`) |
| 429 | Rate limit en POST de creación |

El cliente **no** puede enviar `user_id` ni `municipality_id`; el servidor los resuelve desde la sesión y la junta.

### Motor de base de datos

| Aspecto | MySQL (producción / pruebas aisladas) | SQLite (PHPUnit por defecto) |
|---------|----------------------------------------|------------------------------|
| `pending_slot` | Columna generada `STORED` | Columna nullable + asignación en `saving` del modelo |
| UNIQUE pendiente | Índice real sobre `(group_id, user_id, pending_slot)` | Mismo índice; integridad equivalente en tests |
| Cooldown tras rechazo | API (`rejected_at`) y panel (`group_membership_events.event = rejected`) | Igual a nivel aplicación |

## Referencias

- Dominio: [gestion-juntas.md](gestion-juntas.md)
- Auth móvil: [mobile-auth-api.md](mobile-auth-api.md)
