# Moderación de contenido — Fase 3 y 5D

## Reglas

- La aprobación de propuestas vecinales la realizan **presidente o moderador activo** de la misma junta.
- **Prohibida** la autoaprobación (`author_id === reviewer`).
- Los **administradores municipales** supervisan, ocultan y archivan; **no aprueban** propuestas comunitarias.
- Juntas suspendidas/inactivas: sin nuevas publicaciones ni aprobaciones.

## Auditoría de publicaciones

Eventos en `post_moderation_events` y eventos Laravel (`PostRevisionSubmitted`, `PostRevisionApproved`, etc.) para futuras notificaciones. El ciclo de vida de la publicación (`created`, `submitted`, `approved`, `hidden`, `restored`, `archived`, …) es independiente de la resolución de reportes.

## Panel

- Cola de moderación: solo lectura municipal.
- Reportes de contenido: bandeja y detalle en Filament; las transiciones administrativas existen desde la fase 5D (no antes).

## Reportes de publicaciones

### Creación desde Flutter

El vecino autenticado envía `POST /api/v1/posts/{post}/reports` (`ReportPostService`). Flutter no envía `reporter_id`; el backend atribuye el reporte al token Sanctum.

**Estado actual (5E.4):** el backend es idempotente **si** el cliente envía `Idempotency-Key` (UUID v4). Flutter genera una UUID v4 por intento, la persiste **antes** del POST y la reutiliza solo en «Comprobar envío». Sin cabecera (clientes antiguos), cada POST válido **crea** una fila nueva (`open`). No hay índice único `(reporter_id, post_id)`.

La API de esta fase reporta **publicaciones**, no comentarios. La columna `post_comment_id` existe en `post_reports` por preparación de esquema; no hay endpoint móvil de reporte de comentarios.

### Bandeja municipal

Recurso Filament `PostReportResource` (`/admin/post-reports`). Listado de solo lectura con filtro por estado y fecha. Sin creación, edición ni borrado. Sin acciones masivas ni edición directa de `status`. El alcance es `municipality_id` de los municipios que el usuario administra; el superadministrador ve todos.

### Detalle administrativo

`ViewPostReport` muestra motivo, detalles, publicación asociada (o su ausencia), responsable, fecha y fundamento. Las acciones de cabecera son:

| Acción | Desde | Hacia | Fundamento |
|--------|--------|--------|------------|
| Tomar en revisión | `open` | `reviewing` | No |
| Resolver | `open` o `reviewing` | `resolved` | Obligatorio, trim, máximo 2000 |
| Descartar | `open` o `reviewing` | `dismissed` | Obligatorio, trim, máximo 2000 |

Todas delegan en `TransitionPostReportService`. No hay una segunda implementación en la tabla.

### Estados

`open` → `reviewing` | `resolved` | `dismissed`.
`reviewing` → `resolved` | `dismissed`.
`resolved` y `dismissed` son terminales.

Convención de campos (sin migración adicional):

- `reviewing`: `resolved_by` es el funcionario que toma el caso; `resolved_at` y `resolution_note` quedan nulos.
- `resolved` / `dismissed`: se persisten `resolved_by`, `resolved_at` y `resolution_note`.

### Permisos

| Permiso | Uso |
|---------|-----|
| `posts.reports.view` | Ver bandeja y detalle |
| `posts.reports.resolve` | Ejecutar transiciones |

El superadministrador necesita el permiso Spatie; el rol no basta. El administrador municipal necesita el permiso **y** membresía activa con cargo `administrador` en el municipio del reporte (`PostReportPolicy`).

### Aislamiento municipal

La policy y el `getEloquentQuery` del recurso filtran por municipios administrados. Un ID de reporte ajeno responde 404. Un administrador de A que además es funcionario (no administrador) de B **no** puede ver ni resolver reportes de B.

### Independencia entre resolver y ocultar

Resolver o descartar un reporte **no** cambia `posts.status`, **no** llama a `HidePostService` ni a `RestorePostService`, y **no** crea eventos `hidden`. Ocultar una publicación es una acción distinta, sobre la cola de publicaciones.

### Auditoría de transiciones

Cuando el reporte tiene `post_id`, `TransitionPostReportService` registra **en la misma transacción**:

| Evento | Transición |
|--------|------------|
| `report_reviewing` | `open` → `reviewing` |
| `report_resolved` | `open`\|`reviewing` → `resolved` |
| `report_dismissed` | `open`\|`reviewing` → `dismissed` |

Campos usados de `post_moderation_events`: `post_id`, `municipality_id`, `actor_user_id`, `event`, `from_status`, `to_status` (estados del **reporte**), `payload.report_id`, `created_at`.

El payload **no** copia `details`, fundamento, nombre ni correo del reportante. Esos datos viven en `post_reports`.

Si el recorder falla, la transacción revierte estado y evento.

### Límites de auditoría

`post_moderation_events.post_id` es `NOT NULL` con FK a `posts`. **No se creó migración** en 5D.5 para relajarlo.

| Situación | Transición | Evento en `post_moderation_events` |
|-----------|------------|-------------------------------------|
| Publicación existente | Sí | Sí, con ese `post_id` |
| Publicación *soft-deleted* | Sí | Sí; la fila de `posts` sigue existiendo |
| `post_id` nulo | Sí; no hay error 500 | No. Trazabilidad solo en `post_reports` |
| Solo `post_comment_id` (sin `post_id`) | Sí | No. No se inventa un `post_id` |
| Publicación eliminada físicamente (`nullOnDelete`) | Sí | No; `post_id` queda nulo |

No se simula un evento completo cuando falta `post_id`.

### Concurrencia

El servicio recarga el reporte con `lockForUpdate` y rechaza un segundo cierre. Las pruebas actuales cubren dos llamadas **secuenciales** (SQLite y el mismo proceso). **No** hay evidencia de dos conexiones MySQL compitiendo por el bloqueo: `phpunit.mysql.xml` solo incluye `tests/Feature/Neighborhoods` y `tests/Smoke`, y 5D.5 no altera ese archivo ni ejecuta scripts de reseteo.

Un test futuro debería seguir el patrón de `MembershipRequestMysqlConcurrencyTest` (workers PHP, `red_vecinal_testing`, dos conexiones) y ampliar el alcance de `phpunit.mysql.xml` con autorización expresa.

### Ausencia de deduplicación backend

Varios reportes `open` sobre la misma publicación son válidos. Un reporte `open` no implica que el contenido ya haya sido moderado.

### Idempotencia de reportes (5E.3–5E.4)

El backend reconoce un replay **solo** cuando hay `Idempotency-Key` válida. Flutter 5E.4 envía esa cabecera, persiste la clave y el payload **antes** del POST, y reutiliza el mismo intento solo con **Comprobar envío**.

#### Esquema (5E.2)

Migración aditiva `2026_11_19_210000_add_idempotency_columns_to_post_reports_table`:

| Columna | Tipo | Nulo | Uso previsto |
|---------|------|------|----------------|
| `idempotency_key` | `string(36)` | sí | UUID v4 del intento |
| `payload_fingerprint` | `string(64)` | sí | SHA-256 hexadecimal del payload canónico |

Índice único compuesto: `(reporter_id, idempotency_key)` (`post_reports_reporter_idempotency_unique`).

No existe `UNIQUE(reporter_id, post_id)`. Los reportes previos quedan con ambas columnas en `NULL`. MySQL 8.4 (InnoDB) y SQLite permiten **varios `NULL`** bajo el único compuesto; dos reportes sin clave del mismo usuario no violan el índice.

La clave se interpreta junto al **usuario autenticado**, no de forma global. La misma clave puede existir para dos `reporter_id` distintos.

#### Contrato HTTP (5E.3)

Cabecera opcional `Idempotency-Key`: UUID v4 (RFC 4122, versión 4, variante 8/9/a/b). **Ausente** = legacy (alta nueva, columnas nulas). **Presente y vacía**, con espacios, de otra versión, múltiple o mal formada = **422** (no se crea fila). Tras validar se persiste en **minúsculas**.

Autorización **antes** del lookup de replay: Sanctum, `view` (404) y `report` (403). La clave no salta visibilidad, publicación no `published` ni aislamiento municipal. El lookup es siempre `(reporter_id del token, clave validada)`; nunca solo por UUID.

`reason_code` y `details` conservan las reglas previas (sin trim extra). El JSON de éxito no cambia: **201** `{ "id", "status" }` con `status` de creación (`open`). Un replay no expone el estado administrativo persistido.

| Caso | Código |
|------|--------|
| **401** | Sin token Sanctum |
| **404** | Sin `view` del post |
| **403** | Con `view` pero sin `report` |
| **422** | Cuerpo inválido, o cabecera presente e inválida |
| **409** | Misma clave y usuario, huella o `post_id` distintos (sin mutar filas) |
| **201** | Alta nueva o replay exacto `{id, status:"open"}` |

El cliente **no** puede fijar `reporter_id` ni `municipality_id` por el cuerpo JSON.

Identidad lógica: `(reporter_id, idempotency_key)`. La publicación y el contenido validado van en la huella. Un replay no reabre el reporte, no toca `resolved_by` / `resolved_at` / `resolution_note` y no genera eventos de moderación.

#### Algoritmo

1. Sin clave: `INSERT` legacy (sin transacción extra ni reintentos).
2. Con clave: hasta **3** intentos de transacción completa. Reintento **solo** ante deadlock MySQL `1213`, lock wait `1205` o `SQLSTATE 40001` con evidencia inequívoca de deadlock. No se reintenta 409, 422, 401/403/404, FK `1452`, UNIQUE de otro índice ni errores desconocidos. Agotar intentos relanza el error; **nunca** se finge un 201.
3. En cada intento: `SELECT` ordinario (sin `FOR UPDATE`) por `(reporter_id autenticado, clave)`. Si existe: comparar `post_id` y `payload_fingerprint`; igual → devolver fila; distinto → **409**. Sin mutación ni eventos.
4. Si no existe: `INSERT` con clave y huella. El UNIQUE `(reporter_id, idempotency_key)` impide duplicados.
5. Colisión **solo** de `post_reports_reporter_idempotency_unique`: rollback de esa transacción y lectura de la fila ganadora **fuera** de ella (visibilidad REPEATABLE READ). Replay o 409. Si la ganadora no es visible, se relanza el SQL **sin** segundo INSERT y **sin** inventar éxito.
6. No hay lock global por usuario. UUID distintas no se serializan a propósito.

#### Huella canónica

`App\Domains\Posts\Support\PostReportIdempotency::fingerprint($postId, $reasonCode, $details)`:

1. JSON UTF-8 sin espacios, `JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES`.
2. Orden fijo de claves: `post_id`, `reason_code`, `details`.
3. `post_id`: número JSON o `null` (nunca string).
4. `reason_code` y `details`: valores **ya validados**, sin trim, sin plegado de mayúsculas, sin NFC.
5. `details` PHP `null` → JSON `null`; string vacío `""` → JSON `""`. Son huellas distintas. En HTTP, el middleware de Laravel convierte `""` en `null` **antes** de validar (comportamiento previo, no introducido en 5E.3): omitir `details` y enviar `""` es el mismo intento. El servicio, si recibe `""` crudo, sigue distinguirlo.
6. SHA-256 del JSON; hex minúsculas de 64 caracteres.

#### Concurrencia

La exclusión la da el UNIQUE, no un `SELECT … FOR UPDATE` sobre una clave ausente (ese patrón produjo deadlock 1213 en MySQL 8.4.13, run `44636447594`: A/E PASS; B/C/D FAIL; F incomplete). Hay tests SQLite de colisión UNIQUE, reintento 1213/1205, agotamiento y recuperación fuera de transacción. La carrera InnoDB a dos procesos (`PostReportIdempotencyMysqlConcurrencyTest` + worker + barrera) se omite en `php artisan test` (SQLite) y **no** forma parte de `phpunit.mysql.xml`. Se ejecuta con `phpunit.mysql.idempotency.xml` en `mysql-idempotency.yml` (`workflow_dispatch`), contra MySQL 8.4 efímero (`red_vecinal_testing`, `127.0.0.1`). **La corrección 5E.5E.2 no se ha vuelto a ejecutar en GitHub Actions; no se afirma que 8.4 pasó.** No ejecutar contra MariaDB de Laragon ni contra el VPS.

#### Cliente Flutter (5E.4)

La app genera una UUID v4 con `Random.secure` (sin paquete extra), en minúsculas, distinta por intento lógico. Se persiste **antes** del POST junto con `reason_code` y `details` en `rv_post_report_outcomes_v2` (Android/iOS: almacenamiento seguro). No hay replay automático al arrancar: el vecino usa **Comprobar envío**, que reenvía la misma URL, clave y payload. Esa acción **puede crear** el reporte si el primer POST nunca llegó; no afirma que solo consulta.

Migración desde `rv_post_report_outcomes_v1`: `confirmed` sigue bloqueando; `uncertain`/`inFlight` sin UUID **no** se recuperan ni se convierten en un POST nuevo. v1 no se borra al escribir v2.

Un 201 se confirma en disco **con** payload; solo después se borra `reason_code`/`details`/UUID (se puede conservar `reportId`). Si esa escritura falla, el intento sigue `uncertain` y recuperable. Un 409 deja el intento en `conflict`. Timeout, red, 5xx, 429, 422 genérico o 201 malformado conservan clave y payload. Un 422 de `reason_code`/`details` o de clave inválida reconocible **sí** libera el vuelo (el servidor no insertó). En **web** el almacén sigue en memoria: la recuperación vale hasta recargar.

Un nuevo `workflow_dispatch` de `.github/workflows/mysql-idempotency.yml` es necesario para validar la corrección transaccional en MySQL 8.4; hasta entonces la concurrencia real **no** se considera aprobada.
