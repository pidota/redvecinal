# API móvil — autenticación (Fase 5.2A)

Autenticación con **Laravel Sanctum** (tokens Bearer). No usa cookies de Filament.

Base: `/api/v1`

## POST `/auth/login`

Rate limit: ver `config/red_vecinal.php` → `mobile_auth` (por correo normalizado + IP).

### Request (JSON)

| Campo | Tipo | Obligatorio |
|-------|------|-------------|
| `email` | string (email) | sí |
| `password` | string | sí |
| `device_name` | string (≤255) | sí |

### Respuesta 200

```json
{
  "token": "1|……",
  "token_type": "Bearer",
  "user": {
    "id": 1,
    "name": "Vecino Ejemplo",
    "email": "vecino@example.com",
    "municipality_memberships": [
      {
        "id": 10,
        "municipality_id": 1,
        "municipality": {
          "id": 1,
          "name": "Chépica",
          "slug": "chepica"
        },
        "role": "funcionario",
        "status": "active"
      }
    ]
  }
}
```

### Errores

| HTTP | Situación | Cuerpo |
|------|-----------|--------|
| 401 | Credenciales incorrectas, usuario inexistente o sin autorización móvil | `{ "message": "Las credenciales proporcionadas no son correctas." }` |
| 422 | Validación (`email`, `password`, `device_name`) | Errores estándar Laravel |
| 429 | Rate limit | `{ "message": "Too Many Attempts." }` |

**Notas**

- No se indica si el correo existe.
- Usuarios solo con membresías de junta **suspendidas** y sin membresía municipal activa reciben el mismo 401.
- Usuario sin membresía municipal activa ni junta activa (y sin rol `super-admin`) recibe el mismo **401** que credenciales inválidas.
- Tokens emitidos aquí llevan `expires_at` según `MOBILE_TOKEN_EXPIRATION_DAYS` (default 90). `config/sanctum.php` → `expiration` permanece `null` para no afectar otros tokens.

### Reglas de autorización para emitir token (`MobileApiAccessService`)

| Situación | ¿Puede obtener token? |
|----------|------------------------|
| `super-admin` (Spatie) | Sí |
| Alguna `municipality_members` **activa** | Sí |
| Alguna `group_members` **activa** | Sí |
| Sin membresía municipal activa ni junta activa (no super-admin) | No (401 uniforme) |
| Solo `group_members` **suspendidas** y sin municipal activa | No (401 uniforme) |
| Solo `municipality_members` **inactive** y sin junta activa | No (401 uniforme) |

El modelo `users` no tiene campo «deshabilitado»; no aplica un estado global de cuenta.

### Rate limiting

- Contadores en **cache** (`CACHE_STORE`; en tests `array`, en producción típicamente `redis` o `database`).
- Cada intento a `POST /auth/login` cuenta (éxito o fallo) hacia el límite por identidad (default 5/min) e IP (default 30/min).
- Tras 5 intentos fallidos con el mismo correo+IP, un intento con **contraseña correcta** recibe **429** hasta que expire la ventana (1 minuto).
- El correo se normaliza con `mb_strtolower(trim(...))` para la búsqueda y para la clave del limitador.

### Membresías tras el login

- El token **no** se invalida automáticamente si suspenden al vecino o inactivan su fila municipal; `GET /me` refleja el estado **actual** de `municipality_memberships` activas.
- El resto de la API sigue aplicando **policies** por petición (p. ej. junta suspendida → 403/404).

## POST `/auth/logout`

**Header:** `Authorization: Bearer {token}`

### Respuesta

| HTTP | Cuerpo |
|------|--------|
| 204 | Sin contenido |

Revoca **solo** el `PersonalAccessToken` asociado al Bearer autenticado (`currentAccessToken()`). Otras sesiones/dispositivos del mismo usuario siguen válidas. No es posible revocar el token de otro usuario sin poseer ese Bearer.

## GET `/me`

**Header:** `Authorization: Bearer {token}`

### Respuesta 200

Mismo shape que `user` en login (`MobileUserResource`, objeto JSON raíz sin envoltorio `data`).

### Errores

| HTTP | Situación |
|------|-----------|
| 401 | Sin token, token inválido o revocado |

## Uso del token

```
Authorization: Bearer {token}
```

Rutas existentes (`/groups`, `/posts`, `/chat`, etc.) ya exigen `auth:sanctum`.

## Multi-municipalidad

Un usuario puede tener varias filas en `municipality_memberships` activas; todas se listan en `municipality_memberships` (sin datos de otros usuarios).

## Seguridad

- Contraseñas con hash bcrypt/argon vía cast `hashed` en `User`.
- No registrar contraseñas ni tokens en logs de aplicación.
- No devolver `password`, `remember_token` ni roles Spatie en estas respuestas.

## Nota de autorización tras el login (M2)

No hay middleware global que invalide tokens al suspender una membresía. Las **policies** de cada recurso deniegan operaciones (p. ej. `403` al consultar una junta tras suspender al vecino). El token sigue válido hasta logout, expiración o revocación explícita.
