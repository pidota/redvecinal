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

El vecino autenticado envía `POST /api/v1/posts/{post}/reports` (`ReportPostService`). Cada solicitud **crea** un reporte en estado `open`. No hay idempotencia ni índice único `(reporter_id, post_id)`. Flutter no envía `reporter_id`; el backend atribuye el reporte al token Sanctum.

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
