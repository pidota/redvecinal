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

## Referencias

- Dominio: [gestion-juntas.md](gestion-juntas.md)
- Auth móvil: [mobile-auth-api.md](mobile-auth-api.md)
